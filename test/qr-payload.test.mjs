// 二维码载荷回归测试（对齐上游 PR #32 的双重挂载路径缺陷）。
//
// 背景：LAN 桥模式下 /m/api/qr-config 返回的 urls 已经自带挂载路径
// （http://ip:3082/m），而 lib/client.js 若再无脑拼一次 mount，二维码内容
// 就变成 …:3082/m/m；App 端 _pathOf() 会把它当作请求前缀 → 扫码后所有请求 404。
//
// 这里不启动 dsh、不联网：把 lib/client.js 按 `window.__ModuleLoader__.load`
// 的打包形态加载进来，用极小号的 React 桩渲染一次「连接移动端设备」组件，
// 再从渲染出的 <img src> 里取回二维码载荷做断言。
//
// 运行：node --test test/qr-payload.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { pathToFileURL } from 'node:url';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const CLIENT_PATH = join(here, '..', 'lib', 'client.js');

/** 极简 jsx 运行时：返回 { type, props } 纯对象树，便于遍历取 src。 */
const jsxRuntime = {
	jsx: (type, props) => ({ type, props: props || {} }),
	jsxs: (type, props) => ({ type, props: props || {} }),
	Fragment: 'Fragment',
};

/** 极简 React：useState/useEffect/useRef 够用，支持两次渲染之间保留状态。 */
function makeReact() {
	let cells = [];
	let cursor = 0;
	let effects = [];

	const react = {
		createElement: (type, props, ...children) => ({
			type,
			props: { ...(props || {}), children: children.length === 1 ? children[0] : children },
		}),
		useState: (init) => {
			const i = cursor++;
			if (!(i in cells)) cells[i] = init;
			return [
				cells[i],
				(v) => {
					cells[i] = typeof v === 'function' ? v(cells[i]) : v;
				},
			];
		},
		useEffect: (fn) => {
			effects.push(fn);
		},
		useRef: (init) => {
			const i = cursor++;
			if (!(i in cells)) cells[i] = { current: init };
			return cells[i];
		},
	};

	return {
		react,
		reset() {
			cells = [];
			cursor = 0;
			effects = [];
		},
		render(Component) {
			cursor = 0;
			effects = [];
			const tree = Component();
			return { tree, effects: effects.slice() };
		},
	};
}

/** 深度遍历元素树，收集 <img> 的 src。 */
function collectImgSrc(node, out = []) {
	if (!node) return out;
	if (Array.isArray(node)) {
		for (const n of node) collectImgSrc(n, out);
		return out;
	}
	if (typeof node !== 'object') return out;
	const props = node.props || {};
	if (node.type === 'img' && typeof props.src === 'string') out.push(props.src);
	if (props.children !== undefined) collectImgSrc(props.children, out);
	return out;
}

/** 把 "DSHREMOTE|<url>|<token>" 拆开。 */
function parsePayload(payload) {
	const parts = payload.split('|');
	assert.equal(parts[0], 'DSHREMOTE', `载荷前缀不对：${payload}`);
	return { url: parts[1], token: parts[2] };
}

/**
 * 用给定后端数据渲染一次组件，返回二维码载荷里的地址。
 *
 * @param {{urls: string[], token?: string, path?: string}} backend /m/api/qr-config 的响应体
 */
async function qrUrlFor(backend) {
	const harness = makeReact();
	const requireStub = (name) => {
		if (name === 'react') return harness.react;
		if (name === 'react/jsx-runtime') return jsxRuntime;
		throw new Error(`未预期的 require：${name}`);
	};

	// 模块顶层立刻执行 window.__ModuleLoader__.load({ factory })。
	let factory = null;
	globalThis.window = {
		__ModuleLoader__: {
			load: (entry) => {
				factory = entry.factory;
			},
		},
		isSecureContext: false,
	};
	globalThis.fetch = async () => ({
		ok: true,
		status: 200,
		json: async () => ({ ok: true, path: '/m', token: 'tok-1234567890', ...backend }),
	});

	const url = pathToFileURL(CLIENT_PATH).href;
	// 每次都用新的 query 避免 ESM 模块缓存把旧的 window 捕获带过来。
	await import(`${url}?case=${encodeURIComponent(JSON.stringify(backend))}`);
	assert.ok(factory, 'lib/client.js 未调用 window.__ModuleLoader__.load');

	const exports = factory(requireStub);
	let Section = null;
	exports.apply({
		slots: {
			inject: (_name, fn) => fn(),
			register: (_opts, Component) => {
				Section = Component;
			},
		},
	});
	assert.ok(Section, 'apply() 未注册设置页 section');

	// 第一帧：loading；跑完 effect（fetch → setState）后再渲染一帧。
	harness.reset();
	const first = harness.render(Section);
	assert.equal(first.effects.length, 1, '组件应注册一个数据拉取 effect');
	for (const effect of first.effects) effect();
	for (let i = 0; i < 5; i++) await new Promise((r) => setTimeout(r, 0));
	const { tree } = harness.render(Section);

	const srcs = collectImgSrc(tree);
	assert.equal(srcs.length, 1, `应恰好渲染一个二维码 <img>，实际 ${srcs.length}`);
	const qrSrc = srcs[0];
	assert.match(qrSrc, /\/qr\.png\?text=/, `二维码地址应指向挂载路径下的 qr.png：${qrSrc}`);
	const text = decodeURIComponent(qrSrc.split('text=')[1]);
	return parsePayload(text);
}

test('LAN 桥模式：url 已带挂载路径时不得再拼一次（回归 /m/m）', async () => {
	const { url } = await qrUrlFor({ urls: ['http://192.168.1.5:3082/m', 'http://127.0.0.1:3082/m'] });
	assert.equal(url, 'http://192.168.1.5:3082/m');
	assert.ok(!url.includes('/m/m'), `二维码里出现双重挂载路径：${url}`);
});

test('旧版服务端：url 不带路径时补上默认挂载路径 /m', async () => {
	const { url } = await qrUrlFor({ urls: ['http://192.168.1.5:3080', 'http://127.0.0.1:3080'] });
	assert.equal(url, 'http://192.168.1.5:3080/m');
});

test('自定义挂载路径：按服务端返回的 path 生效，且不重复拼接', async () => {
	const { url } = await qrUrlFor({ urls: ['http://192.168.1.5:3080/mr'], path: '/mr' });
	assert.equal(url, 'http://192.168.1.5:3080/mr');
});

test('地址带尾斜杠（旧服务端）：归一后只拼一次挂载路径', async () => {
	const { url } = await qrUrlFor({ urls: ['http://192.168.1.5:3080/', 'http://127.0.0.1:3080/'] });
	assert.equal(url, 'http://192.168.1.5:3080/m');
});

test('口令随载荷下发，且优先选非回环地址', async () => {
	const { url, token } = await qrUrlFor({ urls: ['http://127.0.0.1:3080/m', 'http://10.0.0.9:3080/m'] });
	assert.equal(token, 'tok-1234567890');
	assert.equal(url, 'http://10.0.0.9:3080/m', '应跳过回环地址');
});
