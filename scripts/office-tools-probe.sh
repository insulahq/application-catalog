#!/usr/bin/env bash
# In-container probe for the apache-php-office runtime. Piped into the image by
# scripts/check-office-tools.sh (`docker run -i … bash -s`) — never bind-mounted,
# so it also works against a remote Docker daemon.
#
# Everything here runs as the image's default user (www-data), because that is
# who PHP-FPM and the Moodle cron CLI are, and a conversion that only works as
# root works for nobody.
#
# The unoconv calls mirror Moodle exactly — see
# public/files/converter/unoconv/classes/converter.php:
#   is_minimum_version_met()    `unoconv --version`, matched /unoconv (\d+\.\d+)/, >= 0.7
#   fetch_supported_formats()   `unoconv --show`, read from STDERR ONLY, scanned /\[\.(.*)\]/
#   start_document_conversion() `unoconv -f pdf -o OUT IN`, from a temp cwd
set -uo pipefail

fails=0
ok()  { printf '  OK   %s\n' "$1"; }
bad() { printf '  FAIL %s\n' "$1"; fails=$((fails + 1)); }

echo "-- running as $(id -un) --"
[ "$(id -un)" = "www-data" ] || bad "image does not default to the www-data user (got $(id -un))"

# 1. Binaries where Moodle's Site administration → System paths defaults expect
#    them. A tool one directory away from the default is a tool every tenant has
#    to be told to reconfigure.
for path in /usr/bin/gs /usr/bin/pdftoppm /usr/bin/unoconv /usr/bin/soffice \
            /usr/bin/dot /usr/bin/aspell /usr/bin/python3 /usr/bin/du; do
  if [ -x "$path" ]; then ok "$path present"; else bad "$path missing"; fi
done

# 2. `unoconv --version` through Moodle's own gate: its regex, and its >= 0.7.
version_out="$(/usr/bin/unoconv --version 2>/dev/null)"
version="$(printf '%s\n' "$version_out" | sed -nE 's/.*unoconv ([0-9]+\.[0-9]+).*/\1/p' | head -1)"
if [ -z "$version" ]; then
  bad "unoconv --version does not match Moodle's /unoconv ([0-9]+\.[0-9]+)/: ${version_out:-<no output>}"
elif awk -v v="$version" 'BEGIN { exit !(v + 0 >= 0.7) }'; then
  ok "unoconv --version reports $version (Moodle requires >= 0.7)"
else
  bad "unoconv reports $version, below Moodle's minimum of 0.7"
fi

# 3. `unoconv --show` must land on STDERR — Moodle proc_opens a pipe on fd 2
#    only, so a list printed to stdout reads back as "no formats supported" and
#    every conversion is refused before it starts.
show_stderr="$(/usr/bin/unoconv --show 2>&1 >/dev/null)"
show_stdout="$(/usr/bin/unoconv --show 2>/dev/null)"
formats="$(printf '%s\n' "$show_stderr" | sed -nE 's/.*\[\.([^]]*)\].*/\1/p' | sort -u | tr '\n' ' ')"
if [ -n "$show_stdout" ]; then
  bad "unoconv --show wrote to stdout; Moodle only reads stderr"
else
  ok "unoconv --show writes to stderr only"
fi
for want in pdf docx odt rtf txt xlsx pptx; do
  case " $formats " in
    *" $want "*) ok "--show advertises .$want" ;;
    *) bad "--show does not advertise .$want (Moodle would refuse that conversion)" ;;
  esac
done

# 4. The real conversion, run the way Moodle runs it: cwd is a fresh temp
#    directory, output named explicitly with -o.
work="$(mktemp -d)"
cd "$work" || { echo "FAIL: cannot cd into $work" >&2; exit 1; }
printf 'Hello Moodle. Submitted work, converted for annotation.\n' > essay.txt
printf '{\\rtf1\\ansi Rich text submission for annotation.\\par}\n' > essay.rtf
printf 'name,mark\nAda,97\nAlan,95\n' > marks.csv

convert() { # label input
  local label="$1" input="$2" out
  out="${input%.*}.pdf"
  if ! /usr/bin/unoconv -f pdf -o "$out" "$input" 2>/tmp/unoconv.err; then
    bad "$label: unoconv exited non-zero: $(tr -d '\n' < /tmp/unoconv.err)"
    return
  fi
  [ -f "$out" ] || { bad "$label: no output file at $out"; return; }
  [ -s "$out" ] || { bad "$label: output file is empty"; return; }
  [ "$(head -c 4 "$out")" = "%PDF" ] || { bad "$label: output is not a PDF"; return; }
  ok "$label -> $(wc -c < "$out") byte PDF"
}

convert "txt to pdf" essay.txt
convert "rtf to pdf" essay.rtf

# Round-trip through the Office formats teachers actually upload. Generating
# them with LibreOffice itself keeps binary fixtures out of the repository.
if /usr/bin/unoconv -f docx -o submission.docx essay.txt 2>/tmp/docx.err && [ -s submission.docx ]; then
  ok "generated a .docx fixture"
  convert "docx to pdf" submission.docx
else
  bad "could not generate a .docx fixture: $(tr -d '\n' < /tmp/docx.err)"
fi
if /usr/bin/unoconv -f xlsx -o marks.xlsx marks.csv 2>/tmp/xlsx.err && [ -s marks.xlsx ]; then
  ok "generated a .xlsx fixture"
  convert "xlsx to pdf" marks.xlsx
else
  bad "could not generate a .xlsx fixture: $(tr -d '\n' < /tmp/xlsx.err)"
fi

# 5. Ghostscript over the produced PDF with the flags assignfeedback_editpdf
#    uses to rasterise a submission page. This is the step that is dark without
#    ghostscript, and the reason this image exists.
if [ -s essay.pdf ]; then
  if /usr/bin/gs -q -sDEVICE=png16m -dSAFER -r100 -dBATCH -dNOPAUSE \
       -sOutputFile="$work/page%d.png" "$work/essay.pdf" >/dev/null 2>/tmp/gs.err \
     && [ -s "$work/page1.png" ]; then
    ok "ghostscript rasterised page 1 ($(wc -c < "$work/page1.png") bytes)"
  else
    bad "ghostscript could not rasterise the PDF: $(tr -d '\n' < /tmp/gs.err)"
  fi
  if /usr/bin/pdftoppm -png -r 100 "$work/essay.pdf" "$work/ppm" >/dev/null 2>/tmp/ppm.err \
     && ls "$work"/ppm*.png > /dev/null 2>&1; then
    ok "pdftoppm rasterised the PDF"
  else
    bad "pdftoppm could not rasterise the PDF: $(tr -d '\n' < /tmp/ppm.err)"
  fi
else
  bad "no PDF to rasterise — an earlier conversion failed"
fi

# 6. Two conversions at once must not collide over a LibreOffice user profile.
#    Moodle drains its adhoc conversion queue back-to-back, and a shared profile
#    makes the second invocation die with "another instance is accessing".
/usr/bin/unoconv -f pdf -o par1.pdf essay.txt 2>/tmp/p1.err &
p1=$!
/usr/bin/unoconv -f pdf -o par2.pdf essay.rtf 2>/tmp/p2.err &
p2=$!
rc=0
wait "$p1" || rc=1
wait "$p2" || rc=1
if [ "$rc" -eq 0 ] && [ -s par1.pdf ] && [ -s par2.pdf ]; then
  ok "two concurrent conversions both produced output"
else
  bad "concurrent conversions collided: $(tr -d '\n' < /tmp/p1.err) $(tr -d '\n' < /tmp/p2.err)"
fi

cd /
rm -rf "$work"

if [ "$fails" -gt 0 ]; then
  echo "FAIL: $fails office-toolchain check(s) failed" >&2
  exit 1
fi
echo "OK: office toolchain verified end to end"
