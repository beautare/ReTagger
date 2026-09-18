#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

const ROOT_DIR = path.join(__dirname, '..');
const PACKAGE_JSON_PATH = path.join(ROOT_DIR, 'package.json');
const PBXPROJ_PATH = path.join(ROOT_DIR, 'ReTagger.xcodeproj', 'project.pbxproj');
const METADATA_DIR = path.join(ROOT_DIR, 'metadata');

const arg = process.argv[2] || 'patch';

// 1. 读取当前基准版本（优先以 project.pbxproj 的 MARKETING_VERSION 为真理源）
let currentVersion = '1.0.0';
if (fs.existsSync(PBXPROJ_PATH)) {
  const pbxContent = fs.readFileSync(PBXPROJ_PATH, 'utf8');
  const match = pbxContent.match(/MARKETING_VERSION = ([0-9.]+);/);
  if (match && match[1] && match[1] !== '1.0') {
    currentVersion = match[1];
  }
}
if (fs.existsSync(PACKAGE_JSON_PATH)) {
  const pkg = JSON.parse(fs.readFileSync(PACKAGE_JSON_PATH, 'utf8'));
  if (pkg.version && semverCompare(pkg.version, currentVersion) > 0) {
    currentVersion = pkg.version;
  }
}

function semverCompare(a, b) {
  const pa = a.split('.').map(Number);
  const pb = b.split('.').map(Number);
  for (let i = 0; i < 3; i++) {
    const diff = (pa[i] || 0) - (pb[i] || 0);
    if (diff !== 0) return diff;
  }
  return 0;
}

let newVersion = '';
if (/^[0-9]+\.[0-9]+\.[0-9]+$/.test(arg)) {
  newVersion = arg;
} else {
  const parts = currentVersion.split('.').map(Number);
  if (arg === 'major') {
    parts[0] += 1;
    parts[1] = 0;
    parts[2] = 0;
  } else if (arg === 'minor') {
    parts[1] += 1;
    parts[2] = 0;
  } else {
    // patch
    parts[2] += 1;
  }
  newVersion = parts.join('.');
}

// 同步写入 package.json
let oldPkgVersion = '';
if (fs.existsSync(PACKAGE_JSON_PATH)) {
  const pkg = JSON.parse(fs.readFileSync(PACKAGE_JSON_PATH, 'utf8'));
  oldPkgVersion = pkg.version;
  pkg.version = newVersion;
  fs.writeFileSync(PACKAGE_JSON_PATH, JSON.stringify(pkg, null, 2) + '\n');
  console.log(`📦 package.json: ${oldPkgVersion} → ${newVersion}`);
}

// 2. 更新 project.pbxproj 的 MARKETING_VERSION 和 CURRENT_PROJECT_VERSION
if (fs.existsSync(PBXPROJ_PATH)) {
  let pbx = fs.readFileSync(PBXPROJ_PATH, 'utf8');

  // 替换主 target 的 MARKETING_VERSION（排除测试 target 的 1.0）
  pbx = pbx.replace(/MARKETING_VERSION = [0-9.]+;/g, (match) => {
    if (match.includes('1.0;')) return match;
    return `MARKETING_VERSION = ${newVersion};`;
  });

  const now = new Date();
  const yy = String(now.getFullYear()).slice(-2);
  const mm = String(now.getMonth() + 1).padStart(2, '0');
  const dd = String(now.getDate()).padStart(2, '0');
  const hh = String(now.getHours()).padStart(2, '0');
  const min = String(now.getMinutes()).padStart(2, '0');
  const newBuild = `${yy}${mm}${dd}${hh}${min}`;

  pbx = pbx.replace(/CURRENT_PROJECT_VERSION = [0-9]+;/g, (match) => {
    if (match.includes(' 1;')) return match;
    return `CURRENT_PROJECT_VERSION = ${newBuild};`;
  });

  fs.writeFileSync(PBXPROJ_PATH, pbx);
  console.log(`🛠️  project.pbxproj: MARKETING_VERSION → ${newVersion}, CURRENT_PROJECT_VERSION → ${newBuild}`);
}

// 3. 准备 metadata/version/<newVersion>（从已有有效版本复制模板）
const newMetaDir = path.join(METADATA_DIR, 'version', newVersion);
const versionParent = path.join(METADATA_DIR, 'version');
if (fs.existsSync(versionParent)) {
  const existingVersions = fs.readdirSync(versionParent).filter(d => {
    if (d.startsWith('.') || d === newVersion) return false;
    const dirPath = path.join(versionParent, d);
    return fs.statSync(dirPath).isDirectory() && fs.readdirSync(dirPath).some(f => f.endsWith('.json'));
  });

  if (existingVersions.length > 0) {
    existingVersions.sort((a, b) => a.localeCompare(b, undefined, { numeric: true }));
    const baseVersion = existingVersions[existingVersions.length - 1];
    fs.mkdirSync(newMetaDir, { recursive: true });
    const baseDir = path.join(versionParent, baseVersion);
    for (const f of fs.readdirSync(baseDir)) {
      if (f.endsWith('.json')) {
        fs.copyFileSync(path.join(baseDir, f), path.join(newMetaDir, f));
      }
    }
    console.log(`📄 已从 ${baseVersion} 复制元数据模板至 metadata/version/${newVersion}`);
  }
}

console.log(`\n✅ 版本升级完成: v${newVersion}`);
console.log(`💡 下一步：检查并更新 metadata/version/${newVersion}/*.json 的 whatsNew，然后运行 npm run deploy:appstore`);
