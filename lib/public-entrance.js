/**
 * 公网 / 穿透入口（config.publicUrls）归一。
 *
 * 局域网明文 HTTP 继续允许：回环、RFC1918、链路本地、CGNAT（Tailscale 的 100.64/10），
 * 以及 .local / .lan / .home / .internal / .home.arpa 主机名。
 * 这些地址上的 token 不出可信网络（虚拟组网本身还有一层加密）。
 *
 * 非局域网的 http:// 默认不进入二维码和 bootstrap 候选地址——口令会写进二维码并明文离开电脑。
 * allowInsecurePublicHttp 是显式放行；放行后仍记入 insecure，方便日志和设置页继续警告。
 *
 * 判定要和 App 的 dsh-mobile-app/lib/net_safety.dart 保持一致。
 */

const PRIVATE_DNS_SUFFIXES = [".local", ".lan", ".home", ".internal", ".localhost", ".home.arpa"];

/** @param {string} host URL.hostname（无方括号、无端口） */
export function isPrivateLanHost(host) {
	let h = String(host ?? "").trim().toLowerCase().replace(/%.*$/, "");
	if (h.startsWith("[") && h.endsWith("]")) h = h.slice(1, -1);
	if (h.endsWith(".")) h = h.slice(0, -1);
	if (h === "" || h === "localhost" || h === "::1") return h !== "";
	if (PRIVATE_DNS_SUFFIXES.some((suffix) => h.endsWith(suffix))) return true;
	if (h.includes(":")) return isPrivateIpv6(h);
	return isPrivateIpv4(h);
}

function isPrivateIpv4(host) {
	const parts = host.split(".");
	if (parts.length !== 4) return false;
	const octets = [];
	for (const part of parts) {
		if (!/^\d{1,3}$/.test(part)) return false;
		const n = Number(part);
		if (n > 255) return false;
		octets.push(n);
	}
	const [a, b] = octets;
	if (a === 10 || a === 127 || a === 0) return true;
	if (a === 192 && b === 168) return true;
	if (a === 172 && b >= 16 && b <= 31) return true;
	if (a === 169 && b === 254) return true;
	// 100.64.0.0/10 — CGNAT，Tailscale 用这段。
	if (a === 100 && b >= 64 && b <= 127) return true;
	return false;
}

function isPrivateIpv6(host) {
	if (host === "::1") return true;
	const first = host.split(":")[0];
	if (!first) return false;
	const n = Number.parseInt(first, 16);
	if (!Number.isFinite(n)) return false;
	// fc00::/7
	if (n >= 0xfc00 && n <= 0xfdff) return true;
	// fe80::/10
	if (n >= 0xfe80 && n <= 0xfebf) return true;
	return false;
}

/**
 * @param {unknown} publicUrls
 * @param {{ allowInsecurePublicHttp?: boolean }} [options]
 * @returns {{ origins: string[], insecure: Array<{ input: string, origin: string, included: boolean }> }}
 */
export function resolvePublicEntrances(publicUrls, { allowInsecurePublicHttp = false } = {}) {
	const origins = [];
	const insecure = [];
	const list = Array.isArray(publicUrls) ? publicUrls : [];
	for (const raw of list) {
		const s = String(raw ?? "").trim();
		if (!/^https?:\/\//i.test(s)) continue;
		let url;
		try {
			url = new URL(s);
		} catch {
			continue;
		}
		if (!url.hostname) continue;
		const origin = `${url.protocol}//${url.host}`;
		if (url.protocol === "http:" && !isPrivateLanHost(url.hostname)) {
			const included = allowInsecurePublicHttp === true;
			if (!insecure.some((item) => item.origin === origin)) {
				insecure.push({ input: s, origin, included });
			}
			if (!included) continue;
		}
		if (!origins.includes(origin)) origins.push(origin);
	}
	return { origins, insecure };
}

/** 启动日志用的一句中文说明。included=false 表示已经从二维码里拿掉。 */
export function insecurePublicHttpWarning(item) {
	if (item.included) {
		return `mobile-remote: 公网入口 ${item.origin} 使用明文 HTTP（allowInsecurePublicHttp 已开启）。访问口令会写入二维码并在网络上明文传输，建议改为 https://。`;
	}
	return `mobile-remote: 公网入口 ${item.origin} 使用明文 HTTP，已从二维码和候选地址中排除。访问口令不能经公网明文传输。请改用 https://；若确认接受风险，设置 allowInsecurePublicHttp: true 后重启。`;
}
