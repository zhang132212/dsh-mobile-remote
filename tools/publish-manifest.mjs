#!/usr/bin/env node
// 发布签名清单（v3.2.1）——App 应用内更新的信任根产出工具。
//
// 用法：
//   node tools/publish-manifest.mjs \
//     --tag v3.2.1 --sequence 4 \
//     [--apk <path>] [--plugin <tgz>] [--notes <file>] \
//     [--repo owner/name] [--upload]
//
// 做了什么：
//   1. 校验三处版本一致（pubspec versionName / +versionCode / tag）；
//   2. 算 APK 与插件包的 sha256 + sizeBytes；
//   3. 按 PRD §5.1 组装 manifest（除 signatures 外全部字段参与签名）；
//   4. 用 Ed25519 私钥对 **JCS（RFC 8785）规范化**后的字节签名（base64url）；
//   5. 写出 update.json；`--upload` 时把它（以及缺失的 APK/tgz）上传到 GitHub Release。
//
// 私钥默认位置：~/.dsh/mobile-remote/release-keys/<keyId>.pem（PKCS8 PEM，绝不进 git）。
// 公钥必须与 App 内置的 trusted_keys.dart 一致，否则 App 验签失败、拒绝更新。
import { createHash, createPrivateKey, sign as edSignRaw } from 'node:crypto'
import { readFileSync, writeFileSync, existsSync } from 'node:fs'
import { homedir } from 'node:os'
import { join, dirname, basename } from 'node:path'
import { fileURLToPath } from 'node:url'

import { jcs, b64u } from '../lib/update-crypto.js'

const HERE = dirname(fileURLToPath(import.meta.url))
const REPO_ROOT = join(HERE, '..')
const APP_DIR = join(REPO_ROOT, 'dsh-mobile-app')

/** 与 App 内置公钥表对应的 keyId（换钥时改这里并同步 trusted_keys.dart）。 */
const KEY_ID = 'dsh-release-eun'
const DEFAULT_REPO = 'zhang132212/dsh-mobile-remote'

function parseArgs(argv) {
  const out = { upload: false }
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]
    if (a === '--upload') { out.upload = true; continue }
    if (a.startsWith('--')) { out[a.slice(2)] = argv[++i] }
  }
  return out
}

function die(msg) {
  console.error('✗ ' + msg)
  process.exit(1)
}

function sha256File(p) {
  const h = createHash('sha256')
  h.update(readFileSync(p))
  return h.digest('hex')
}

/** 从 pubspec.yaml 读 version / versionCode。 */
function readPubspec() {
  const text = readFileSync(join(APP_DIR, 'pubspec.yaml'), 'utf8')
  const m = /^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$/m.exec(text)
  if (!m) die('pubspec.yaml 里找不到 `version: x.y.z+N`')
  return { versionName: m[1], versionCode: Number(m[2]) }
}

/**
 * 插件版本（本仓库根的 package.json）。
 * PRD §5.1.2 的交叉校验要求：`minPluginVersion` ≤ 新插件版本，
 * 所以这里必须取**插件自己**的版本，不能拿 App 版本顶上。
 */
function readPluginVersion() {
  const pkg = JSON.parse(readFileSync(join(REPO_ROOT, 'package.json'), 'utf8'))
  if (!pkg.version) die('package.json 缺少 version')
  return { versionName: pkg.version }
}

async function api(method, path, body, token, { raw = null, contentType = 'application/json' } = {}) {
  const url = path.startsWith('http') ? path : `https://api.github.com${path}`
  for (let i = 1; i <= 5; i++) {
    try {
      const res = await fetch(url, {
        method,
        headers: {
          Authorization: `Bearer ${token}`,
          Accept: 'application/vnd.github+json',
          'User-Agent': 'dsh-publish-manifest',
          ...(raw ? { 'Content-Type': contentType } : {}),
        },
        body: raw ?? (body ? JSON.stringify(body) : undefined),
      })
      const text = await res.text()
      if (!res.ok) throw new Error(`HTTP ${res.status} ${text.slice(0, 200)}`)
      return text ? JSON.parse(text) : null
    } catch (e) {
      if (i === 5) throw e
      console.error(`  · 第 ${i} 次失败，4s 后重试：${e.message}`)
      await new Promise((r) => setTimeout(r, 4000))
    }
  }
}

async function uploadAsset(token, repo, releaseId, file, name, contentType) {
  const bytes = readFileSync(file)
  const url = `https://uploads.github.com/repos/${repo}/releases/${releaseId}/assets?name=${encodeURIComponent(name)}`
  for (let i = 1; i <= 5; i++) {
    try {
      const res = await fetch(url, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${token}`,
          Accept: 'application/vnd.github+json',
          'User-Agent': 'dsh-publish-manifest',
          'Content-Type': contentType,
          'Content-Length': String(bytes.length),
        },
        body: bytes,
      })
      const text = await res.text()
      if (!res.ok) throw new Error(`HTTP ${res.status} ${text.slice(0, 200)}`)
      return JSON.parse(text)
    } catch (e) {
      if (i === 5) throw e
      console.error(`  · 上传第 ${i} 次失败，8s 后重试：${e.message}`)
      await new Promise((r) => setTimeout(r, 8000))
    }
  }
}

async function main() {
  const args = parseArgs(process.argv.slice(2))
  const repo = args.repo ?? DEFAULT_REPO
  const tag = args.tag ?? die('缺少 --tag')
  const sequence = Number(args.sequence ?? die('缺少 --sequence（必须单调递增）'))

  const { versionName, versionCode } = readPubspec()
  const pluginVersion = readPluginVersion().versionName
  if (tag !== `v${versionName}` && !args.skipTagCheck) {
    die(`tag 与 pubspec 版本不一致：tag=${tag} pubspec=v${versionName}`)
  }

  const apk = args.apk ?? die('缺少 --apk')
  if (!existsSync(apk)) die(`APK 不存在：${apk}`)
  const plugin = args.plugin
  if (plugin && !existsSync(plugin)) die(`插件包不存在：${plugin}`)

  const apkInfo = { fileName: basename(apk), sizeBytes: readFileSync(apk).length, sha256: sha256File(apk) }
  const pluginInfo = plugin
    ? { fileName: basename(plugin), sizeBytes: readFileSync(plugin).length, sha256: sha256File(plugin) }
    : null

  if (!pluginInfo) die('缺少 --plugin：manifest 的 artifacts.plugin 是必填字段（App 端解析会直接拒绝）')

  // ── 组装 manifest（除 signatures 外全部字段参与签名） ──
  const manifest = {
    schemaVersion: 1,
    sequence,
    channel: 'stable',
    publishedAt: new Date().toISOString().replace(/\.\d{3}Z$/, 'Z'),
    minPluginVersion: pluginVersion,
    minAppVersionCode: versionCode,
    artifacts: {
      app: {
        artifactId: 'dsh-remote-apk',
        fileName: apkInfo.fileName,
        versionName,
        versionCode,
        sizeBytes: apkInfo.sizeBytes,
        sha256: apkInfo.sha256,
      },
      plugin: {
        artifactId: 'dsh-remote-plugin',
        fileName: pluginInfo.fileName,
        versionName: pluginVersion,
        sizeBytes: pluginInfo.sizeBytes,
        sha256: pluginInfo.sha256,
      },
    },
  }

  const payload = jcs(manifest)
  const keyPath = args.key ?? join(homedir(), '.dsh', 'mobile-remote', 'release-keys', `${KEY_ID}.pem`)
  if (!existsSync(keyPath)) die(`私钥不存在：${keyPath}`)
  const priv = createPrivateKey({ key: readFileSync(keyPath, 'utf8'), format: 'pem' })
  const signature = b64u(edSignRaw(null, Buffer.from(payload, 'utf8'), priv))

  const signed = { ...manifest, signatures: [{ keyId: KEY_ID, signature }] }
  const outPath = args.out ?? join(REPO_ROOT, 'update.json')
  writeFileSync(outPath, JSON.stringify(signed, null, 2) + '\n', 'utf8')

  console.log('=== 签名清单已生成 ===')
  console.log(`  版本        : ${versionName}+${versionCode}  (tag ${tag}, sequence ${sequence})`)
  console.log(`  APK         : ${apkInfo.fileName}  ${apkInfo.sizeBytes} B  sha256=${apkInfo.sha256.slice(0, 16)}…`)
  console.log(`  插件包      : ${pluginInfo.fileName}  ${pluginInfo.sizeBytes} B`)
  console.log(`  keyId       : ${KEY_ID}`)
  console.log(`  canonical   : ${payload.length} 字符`)
  console.log(`  输出        : ${outPath}`)

  if (!args.upload) {
    console.log('\n（未加 --upload，仅生成本地文件）')
    return
  }

  const token = process.env.GITHUB_TOKEN
  if (!token) die('--upload 需要环境变量 GITHUB_TOKEN')

  const release = await api('GET', `/repos/${repo}/releases/tags/${tag}`, null, token)
  const assets = await api('GET', `/repos/${repo}/releases/${release.id}/assets`, null, token)
  const have = new Set(assets.map((a) => a.name))

  for (const [file, name, ct] of [
    [outPath, 'update.json', 'application/json'],
    [apk, apkInfo.fileName, 'application/vnd.android.package-archive'],
    [plugin, pluginInfo.fileName, 'application/gzip'],
  ]) {
    if (have.has(name)) {
      console.log(`  已存在，跳过：${name}`)
      continue
    }
    const a = await uploadAsset(token, repo, release.id, file, name, ct)
    console.log(`  已上传：${a.name} (${a.size} B)`)
  }
  console.log(`\n完成：${release.html_url}`)
}

main().catch((e) => die(e.stack ?? String(e)))
