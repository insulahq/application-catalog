#!/usr/bin/env node

/**
 * Unified catalog validator — validates ALL entries (applications, runtimes,
 * databases, services) against the JSON Schema, checks Helm chart structure,
 * cross-references catalog.json, and verifies image tag pinning.
 *
 * Usage: node scripts/validate.mjs
 * Exit code 0 = all valid, 1 = errors found
 */

import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import Ajv from 'ajv';
import addFormats from 'ajv-formats';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, '..');

let errors = 0;
let warnings = 0;

function error(msg) {
    console.error(`  ✗ ${msg}`);
    errors++;
}

function warn(msg) {
    console.warn(`  ⚠ ${msg}`);
    warnings++;
}

function ok(msg) {
    console.log(`  ✓ ${msg}`);
}

// ── Load schema ──────────────────────────────────────────────────────────────

const schemaPath = join(ROOT, 'schema', 'manifest.schema.json');
if (!existsSync(schemaPath)) {
    console.error('FATAL: schema/manifest.schema.json not found');
    process.exit(1);
}

const schema = JSON.parse(readFileSync(schemaPath, 'utf8'));
const ajv = new Ajv({ allErrors: true, strict: false });
addFormats(ajv);
const validate = ajv.compile(schema);

// ── Load catalog.json ────────────────────────────────────────────────────────

console.log('\n📋 Validating catalog.json...');

const catalogPath = join(ROOT, 'catalog.json');
if (!existsSync(catalogPath)) {
    error('catalog.json not found');
    process.exit(1);
}

const catalog = JSON.parse(readFileSync(catalogPath, 'utf8'));

if (!catalog.version) error('catalog.json missing "version" field');
if (!catalog.name) error('catalog.json missing "name" field');
if (!Array.isArray(catalog.entries)) {
    error('catalog.json missing "entries" array');
    process.exit(1);
}
if (catalog.entries.length === 0) {
    error('catalog.json "entries" array is empty');
}

const catalogSet = new Set(catalog.entries);
if (catalogSet.size !== catalog.entries.length) {
    error('catalog.json contains duplicate entries');
}

ok(`catalog.json has ${catalog.entries.length} entries`);

// ── Discover entry directories ───────────────────────────────────────────────

const SKIP_DIRS = new Set(['.git', '.github', 'node_modules', 'schema', 'scripts']);

const dirs = readdirSync(ROOT).filter((name) => {
    const full = join(ROOT, name);
    return statSync(full).isDirectory() && !name.startsWith('.') && !SKIP_DIRS.has(name);
});

// ── Floating tag detection ───────────────────────────────────────────────────

const FLOATING_TAGS = new Set([
    'latest', 'release', 'stable', 'edge', 'nightly',
    'dev', 'canary', 'beta', 'alpha', 'rc',
]);

function checkImageTag(dir, context, image) {
    const colonIdx = image.lastIndexOf(':');
    if (colonIdx === -1 || colonIdx === image.length - 1) {
        error(`${dir}: ${context} image "${image}" has no tag — implicit :latest is not allowed`);
        return;
    }
    const tag = image.slice(colonIdx + 1);
    if (FLOATING_TAGS.has(tag.toLowerCase())) {
        error(`${dir}: ${context} image "${image}" uses floating tag ":${tag}". Pin to a specific version.`);
    }
}

// ── Validate each manifest ───────────────────────────────────────────────────

console.log('\n📦 Validating manifests...\n');

const manifestCodes = new Set();
const typeCount = { application: 0, runtime: 0, database: 0, service: 0 };

for (const dir of dirs) {
    const manifestPath = join(ROOT, dir, 'manifest.json');
    console.log(`  ${dir}/manifest.json`);

    if (!existsSync(manifestPath)) {
        error(`${dir}/manifest.json not found`);
        continue;
    }

    let manifest;
    try {
        manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
    } catch (e) {
        error(`${dir}/manifest.json is not valid JSON: ${e.message}`);
        continue;
    }

    // Schema validation
    const valid = validate(manifest);
    if (!valid) {
        for (const err of validate.errors) {
            const path = err.instancePath || '(root)';
            error(`${dir}: ${path} ${err.message}`);
        }
        continue;
    }

    // Code must match directory name.
    //
    // Two deliberate exceptions: f3b5849 ("feat(static): codes nginx/apache")
    // shortened the catalog CODE for the static entries while the DIRECTORY —
    // and with it the published image name, ghcr.io/.../static-nginx — stayed
    // as-is. The validator was not updated alongside, so `Validate Catalog` has
    // been red on main since 2026-07-28. Listing the pair explicitly keeps the
    // strict check everywhere else, so accidental drift is still caught.
    const CODE_DIR_EXCEPTIONS = { 'static-nginx': 'nginx', 'static-apache': 'apache' };
    if (manifest.code !== dir && CODE_DIR_EXCEPTIONS[dir] !== manifest.code) {
        error(`${dir}: code "${manifest.code}" does not match directory name "${dir}"`);
    }

    // Duplicate code check
    if (manifestCodes.has(manifest.code)) {
        error(`${dir}: duplicate code "${manifest.code}"`);
    }
    manifestCodes.add(manifest.code);

    // Count by type
    if (typeCount[manifest.type] !== undefined) {
        typeCount[manifest.type]++;
    }

    // Icon check
    if (!existsSync(join(ROOT, dir, 'icon.png'))) {
        error(`${dir}: icon.png not found`);
    }

    // ── Type-specific validations ────────────────────────────────────────────

    if (manifest.type === 'application') {
        // Must have at least one component with ingress: true
        const hasIngress = manifest.components.some(
            (c) => c.ports && c.ports.some((p) => p.ingress)
        );
        if (!hasIngress) {
            warn(`${dir}: no component has a port with ingress: true`);
        }

        // Validate host_ports reference valid components
        if (manifest.networking.host_ports) {
            const componentNames = new Set(manifest.components.map((c) => c.name));
            for (const hp of manifest.networking.host_ports) {
                if (!componentNames.has(hp.component)) {
                    error(`${dir}: host_port references unknown component "${hp.component}"`);
                }
            }
        }

        // Parameter keys should be unique
        const paramKeys = manifest.parameters.map((p) => p.key);
        const uniqueKeys = new Set(paramKeys);
        if (uniqueKeys.size !== paramKeys.length) {
            error(`${dir}: duplicate parameter keys found`);
        }
    }

    if (manifest.type === 'runtime') {
        if (manifest.has_dockerfile) {
            const dockerfilePath = join(ROOT, dir, 'Dockerfile');
            if (!existsSync(dockerfilePath)) {
                error(`${dir}: has_dockerfile is true but no Dockerfile found`);
            }
        }
        if (manifest.image === null && !manifest.has_dockerfile) {
            error(`${dir}: image is null but has_dockerfile is false — need one or the other`);
        }
    }

    if (manifest.type === 'database' || manifest.type === 'service') {
        if (!manifest.provides) {
            error(`${dir}: ${manifest.type} entry missing "provides" field`);
        }
    }

    // Health check: must have path or command
    if (manifest.health_check) {
        const hasPath = manifest.health_check.path !== null && manifest.health_check.path !== undefined;
        const hasCommand = manifest.health_check.command !== null && manifest.health_check.command !== undefined;
        if (!hasPath && !hasCommand) {
            warn(`${dir}: health_check has neither "path" nor "command"`);
        }
    }

    // ── Check image tags in components ───────────────────────────────────────

    for (const comp of manifest.components) {
        checkImageTag(dir, `component "${comp.name}"`, comp.image);
    }

    // ── Check supportedVersions ──────────────────────────────────────────────

    if (manifest.supportedVersions) {
        const componentNames = new Set(manifest.components.map((c) => c.name));
        const versionIds = new Set();

        for (const sv of manifest.supportedVersions) {
            if (versionIds.has(sv.version)) {
                error(`${dir}: duplicate supportedVersion "${sv.version}"`);
            }
            versionIds.add(sv.version);

            for (const comp of sv.components) {
                if (!componentNames.has(comp.name)) {
                    error(`${dir}: supportedVersion "${sv.version}" references unknown component "${comp.name}"`);
                }
                checkImageTag(dir, `supportedVersion "${sv.version}" component "${comp.name}"`, comp.image);
            }

            if (sv.upgradeFrom) {
                for (const from of sv.upgradeFrom) {
                    if (!manifest.supportedVersions.some((v) => v.version === from)) {
                        warn(`${dir}: supportedVersion "${sv.version}" upgradeFrom references "${from}" which is not in supportedVersions`);
                    }
                }
            }
        }
    }

    ok(`${dir}: valid (${manifest.type})`);
}

// ── Check Helm chart structure ───────────────────────────────────────────────

console.log('\n⎈ Checking Helm chart structure...\n');

for (const dir of dirs) {
    const chartDir = join(ROOT, dir, 'chart');
    console.log(`  ${dir}/chart/`);

    if (!existsSync(chartDir)) {
        error(`${dir}: chart/ directory not found`);
        continue;
    }

    const requiredFiles = ['Chart.yaml', 'values.yaml'];
    for (const file of requiredFiles) {
        if (!existsSync(join(chartDir, file))) {
            error(`${dir}: chart/${file} not found`);
        }
    }

    const templatesDir = join(chartDir, 'templates');
    if (!existsSync(templatesDir)) {
        error(`${dir}: chart/templates/ directory not found`);
    } else {
        const templates = readdirSync(templatesDir);
        if (templates.length === 0) {
            error(`${dir}: chart/templates/ is empty`);
        } else {
            ok(`${dir}: chart/ valid (${templates.length} template files)`);
        }
    }

    const chartYamlPath = join(chartDir, 'Chart.yaml');
    if (existsSync(chartYamlPath)) {
        const content = readFileSync(chartYamlPath, 'utf8');
        if (!content.includes('apiVersion:')) error(`${dir}: Chart.yaml missing apiVersion`);
        if (!content.includes('name:')) error(`${dir}: Chart.yaml missing name`);
        if (!content.includes('version:')) error(`${dir}: Chart.yaml missing version`);
    }
}

// ── Cross-reference catalog.json ↔ directories ──────────────────────────────

console.log('\n🔗 Cross-referencing catalog.json ↔ directories...');

for (const entry of catalog.entries) {
    if (!dirs.includes(entry)) {
        error(`catalog.json lists "${entry}" but no directory found`);
    }
}

for (const dir of dirs) {
    if (!catalog.entries.includes(dir)) {
        warn(`directory "${dir}" exists but is not listed in catalog.json`);
    }
}

// ── Service dependency consistency ───────────────────────────────────────────

console.log('\n🔗 Checking service dependency consistency...');

const providers = new Map();
for (const dir of dirs) {
    const manifestPath = join(ROOT, dir, 'manifest.json');
    if (!existsSync(manifestPath)) continue;
    try {
        const m = JSON.parse(readFileSync(manifestPath, 'utf8'));
        if (m.provides) {
            if (m.provides.database) {
                providers.set(`database:${m.provides.database.engine}`, {
                    code: m.code,
                    version: m.provides.database.version,
                });
            }
            if (m.provides.redis) {
                providers.set('redis', { code: m.code, version: m.provides.redis.version });
            }
        }
    } catch {
        // already reported
    }
}

for (const dir of dirs) {
    const manifestPath = join(ROOT, dir, 'manifest.json');
    if (!existsSync(manifestPath)) continue;
    try {
        const m = JSON.parse(readFileSync(manifestPath, 'utf8'));
        if (m.services?.database?.required) {
            const hasProvider = m.services.database.engines.some((e) =>
                providers.has(`database:${e.type}`)
            );
            if (!hasProvider) {
                warn(`${dir}: requires database (${m.services.database.engines.map((e) => e.type).join('/')}) but no provider in catalog`);
            }
        }
        if (m.services?.redis?.required) {
            if (!providers.has('redis')) {
                warn(`${dir}: requires redis but no redis provider in catalog`);
            }
        }
    } catch {
        // already reported
    }
}

ok('dependency check complete');

// ── JSON format check ────────────────────────────────────────────────────────

console.log('\n📝 Checking JSON formatting...');

let formatIssues = 0;
for (const dir of dirs) {
    const manifestPath = join(ROOT, dir, 'manifest.json');
    if (!existsSync(manifestPath)) continue;
    const raw = readFileSync(manifestPath, 'utf8');
    try {
        const parsed = JSON.parse(raw);
        const formatted = JSON.stringify(parsed, null, 4) + '\n';
        if (raw !== formatted) {
            warn(`${dir}: manifest.json is not formatted with 4-space indentation`);
            formatIssues++;
        }
    } catch {
        // already reported
    }
}

if (formatIssues === 0) {
    ok('all manifests properly formatted');
} else {
    warn(`${formatIssues} manifest(s) have formatting issues`);
}

// ── Summary ──────────────────────────────────────────────────────────────────

console.log('\n' + '─'.repeat(60));
console.log(`  Types: ${typeCount.application} applications, ${typeCount.runtime} runtimes, ${typeCount.database} databases, ${typeCount.service} services`);

if (errors > 0) {
    console.error(`\n❌ ${errors} error(s), ${warnings} warning(s)\n`);
    process.exit(1);
} else {
    console.log(`\n✅ All ${dirs.length} entries valid, ${warnings} warning(s)\n`);
    process.exit(0);
}
