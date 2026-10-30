// 生成 v3.2.16 的签名 update.json（本地按 PRD §5.1 组装 + Ed25519/JCS 签名）。
//
// 用法：node tools/prepare-release.mjs --apk <path> [--sequence 18] [--out update.json]
//
// 与 tools/publish-manifest.mjs 的区别：这里不依赖本地 plugin tgz（插件未变，
// 直接沿用 v3.2.15 清单里的 fileName/size/sha256），也不上传——只产出可验证的清单。
import { createHash, createPrivateKey, sign as edSignRaw } from 'node:crypto'
import { readFileSync, writeFileSync, existsSync } from 'node:fs'
import { homedir } from 'node:os'
import { dirname, basename, join } from 'node:path'
import { fileURLToPath } from 'node:url'

import { jcs, b64u } from '../lib/update-crypto.js'

const HERE = dirname(fileURLToPath(import.meta.url))
const REPO_ROOT = join(HERE, '..')

const KEY_ID = 'dsh-release-eun'
const PLUGIN = {
  artifactId: 'dsh-remote-plugin',
  fileName: 'dsh-mobile-remote-3.1.5-eun.1.tgz',
  versionName: '3.1.5-eun.1',
  sizeBytes: 4950263,
  sha256: '1902c8725ed991566eccbad64d435035c94c129d1eba13d9bc302e3c76def006',
}

const args = {}
for (let i = 2; i < process.argv.length; i++) {
  const a = process.argv[i]
  if (a.startsWith('--')) args[a.slice(2)] = process.argv[++i]
}

const apkPath = args.apk
if (!apkPath || !existsSync(apkPath)) {
  console.error('用法：node tools/prepare-release.mjs --apk <path> [--plugin <tgz>] [--sequence 18]')
  process.exit(1)
}
const sequence = Number(args.sequence ?? 18)
const versionName = args['version-name'] ?? '3.2.16'
const versionCode = Number(args['version-code'] ?? 39)
const outPath = args.out ?? join(REPO_ROOT, 'update.json')

// 插件包：传了 --plugin 就用它的真实 size/sha256（本地 npm pack 出来的）；
// 不传则沿用 v3.2.15 清单里的值（插件没改动时）。
if (args.plugin) {
  if (!existsSync(args.plugin)) {
    console.error(`插件包不存在：${args.plugin}`)
    process.exit(1)
  }
  PLUGIN.fileName = basename(args.plugin)
  PLUGIN.sizeBytes = readFileSync(args.plugin).length
  PLUGIN.sha256 = createHash('sha256').update(readFileSync(args.plugin)).digest('hex')
}

const apkBytes = readFileSync(apkPath)
const manifest = {
  schemaVersion: 1,
  sequence,
  channel: 'stable',
  publishedAt: new Date().toISOString().replace(/\.\d{3}Z$/, 'Z'),
  minPluginVersion: PLUGIN.versionName,
  minAppVersionCode: versionCode,
  artifacts: {
    app: {
      artifactId: 'dsh-remote-apk',
      fileName: basename(apkPath),
      versionName,
      versionCode,
      sizeBytes: apkBytes.length,
      sha256: createHash('sha256').update(apkBytes).digest('hex'),
    },
    plugin: PLUGIN,
  },
}

const payload = jcs(manifest)
const keyPath = args.key ?? join(homedir(), '.dsh', 'mobile-remote', 'release-keys', `${KEY_ID}.pem`)
const priv = createPrivateKey({ key: readFileSync(keyPath, 'utf8'), format: 'pem' })
const signature = b64u(edSignRaw(null, Buffer.from(payload, 'utf8'), priv))
const signed = { ...manifest, signatures: [{ keyId: KEY_ID, signature }] }

writeFileSync(outPath, JSON.stringify(signed, null, 2) + '\n', 'utf8')

console.log('=== 已生成签名清单（未上传） ===')
console.log(`  版本   : ${versionName}+${versionCode}  sequence=${sequence}`)
console.log(`  APK    : ${manifest.artifacts.app.fileName}  ${manifest.artifacts.app.sizeBytes} B`)
console.log(`  sha256 : ${manifest.artifacts.app.sha256}`)
console.log(`  keyId  : ${KEY_ID}`)
console.log(`  输出   : ${outPath}`)
