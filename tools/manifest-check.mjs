// 发布后自检（v3.2.16）——从 GitHub 拉「最新 Release」，按 App 的规则验一遍：
//   ① update.json 存在且 Ed25519 验签通过（受信公钥取 lib/update-crypto.js）；
//   ② manifest 里的 sequence / versionCode / 文件名与预期一致；
//   ③ Release 里确实有 manifest 指向的那个 APK 资产，且 size 对得上；
//   ④ 顺便报告 README 里的「检查更新」会怎么判（当前 latest vs 指定已安装版本）。
//
// 用法：node tools/manifest-check.mjs --repo zhang132212/dsh-mobile-remote [--expect-code 39]
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

import { trustedReleaseKeys, verifyManifestSignatures } from '../lib/update-crypto.js'

const HERE = dirname(fileURLToPath(import.meta.url))
const REPO_ROOT = join(HERE, '..')

const args = {}
for (let i = 2; i < process.argv.length; i++) {
  const a = process.argv[i]
  if (a.startsWith('--')) args[a.slice(2)] = process.argv[++i]
}
const repo = args.repo ?? 'zhang132212/dsh-mobile-remote'
const expectCode = args['expect-code'] ? Number(args['expect-code']) : null
const expectSeq = args['expect-sequence'] ? Number(args['expect-sequence']) : null

const H = { 'User-Agent': 'dsh-manifest-check', Accept: 'application/vnd.github+json' }

async function main() {
  const rel = await fetch(`https://api.github.com/repos/${repo}/releases/latest`, { headers: H })
  if (!rel.ok) throw new Error(`拉 latest release 失败 HTTP ${rel.status}`)
  const release = await rel.json()
  console.log(`latest: ${release.tag_name}  (${release.name ?? ''})  draft=${release.draft} pre=${release.prerelease}`)

  const assets = release.assets ?? []
  const manifestAsset = assets.find((a) => a.name === 'update.json')
  if (!manifestAsset) throw new Error('latest release 没有 update.json 资产')

  const res = await fetch(manifestAsset.url, { headers: { ...H, Accept: 'application/octet-stream' } })
  if (!res.ok) throw new Error(`下载 update.json 失败 HTTP ${res.status}`)
  const manifest = await res.json()

  const { signatures, ...unsigned } = manifest
  const keyId = verifyManifestSignatures(unsigned, signatures, trustedReleaseKeys)
  console.log(`验签: ${keyId ? '通过 keyId=' + keyId : '失败（没有受信签名命中）'}`)
  if (!keyId) process.exitCode = 1

  const app = manifest?.artifacts?.app ?? {}
  const plugin = manifest?.artifacts?.plugin ?? {}
  console.log(`sequence=${manifest.sequence}  app=${app.versionName}+${app.versionCode}  plugin=${plugin.versionName}`)
  console.log(`apk 资产名: ${app.fileName}  size=${app.sizeBytes}  sha256=${String(app.sha256).slice(0, 16)}…`)

  const apkAsset = assets.find((a) => a.name === app.fileName)
  if (!apkAsset) {
    console.log('✗ Release 里找不到 manifest 指向的 APK 资产')
    process.exitCode = 1
  } else {
    const ok = apkAsset.size === app.sizeBytes
    console.log(`${ok ? '✓' : '✗'} APK 资产存在，size ${apkAsset.size} / 期望 ${app.sizeBytes}`)
    if (!ok) process.exitCode = 1
  }

  const pluginAsset = assets.find((a) => a.name === plugin.fileName)
  console.log(`${pluginAsset ? '✓' : '·'} 插件资产 ${plugin.fileName} ${pluginAsset ? '存在' : '缺失（可选）'}`)

  if (expectCode != null) {
    const verdict = app.versionCode > expectCode ? '会提示有新版本' : '判定为已是最新'
    console.log(`已安装 versionCode=${expectCode} → ${verdict}`)
    if (app.versionCode <= expectCode) process.exitCode = 1
  }
  if (expectSeq != null && manifest.sequence !== expectSeq) {
    console.log(`✗ sequence=${manifest.sequence}，期望 ${expectSeq}`)
    process.exitCode = 1
  }
}

main().catch((e) => {
  console.error('✗ ' + e.message)
  process.exitCode = 1
})
