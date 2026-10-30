// publicUrls 归一：局域网 http 保留，明文公网默认不进二维码。
// 运行：node --test test/public-entrance.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	insecurePublicHttpWarning,
	isPrivateLanHost,
	resolvePublicEntrances,
} from '../lib/public-entrance.js';

test('局域网、回环、CGNAT、本地域名算私网', () => {
	for (const host of [
		'127.0.0.1',
		'localhost',
		'192.168.1.20',
		'10.1.2.3',
		'172.16.5.5',
		'172.31.255.255',
		'169.254.1.1',
		'100.64.0.7',
		'100.127.0.1',
		'my-pc.local',
		'nas.lan',
		'box.home.arpa',
		'::1',
		'fc00::1',
		'fe80::1',
	]) {
		assert.equal(isPrivateLanHost(host), true, host);
	}
});

test('公网 IP 和普通域名不算私网', () => {
	for (const host of [
		'8.8.8.8',
		'1.2.3.4',
		'100.63.0.1',
		'100.128.0.1',
		'172.15.0.1',
		'172.32.0.1',
		'11.0.0.1',
		'vps.example',
		'xxx.natfrp.com',
		'2001:db8::1',
	]) {
		assert.equal(isPrivateLanHost(host), false, host);
	}
});

test('https 与局域网 http 进入候选，明文公网默认排除', () => {
	const plan = resolvePublicEntrances([
		'https://dsh.example.com/m',
		'http://192.168.1.5:3080/m',
		'http://vps.example:8080/m',
		'http://vps.example:8080/other',
		'ftp://nope.example',
		'not a url',
		'http://[::1]:3080/m',
		'http://[2001:db8::1]:3080/m',
	]);
	assert.deepEqual(plan.origins, [
		'https://dsh.example.com',
		'http://192.168.1.5:3080',
		'http://[::1]:3080',
	]);
	assert.deepEqual(
		plan.insecure.map((item) => ({ origin: item.origin, included: item.included })),
		[
			{ origin: 'http://vps.example:8080', included: false },
			{ origin: 'http://[2001:db8::1]:3080', included: false },
		],
	);
	assert.match(insecurePublicHttpWarning(plan.insecure[0]), /已从二维码和候选地址中排除/);
	assert.match(insecurePublicHttpWarning(plan.insecure[0]), /allowInsecurePublicHttp/);
});

test('allowInsecurePublicHttp 放行明文公网，但仍标记为不安全', () => {
	const plan = resolvePublicEntrances(['http://vps.example:8080'], {
		allowInsecurePublicHttp: true,
	});
	assert.deepEqual(plan.origins, ['http://vps.example:8080']);
	assert.equal(plan.insecure.length, 1);
	assert.equal(plan.insecure[0].included, true);
	assert.match(insecurePublicHttpWarning(plan.insecure[0]), /已开启/);
});

test('空配置与非数组不抛', () => {
	assert.deepEqual(resolvePublicEntrances(undefined), { origins: [], insecure: [] });
	assert.deepEqual(resolvePublicEntrances(null), { origins: [], insecure: [] });
});
