// DSH Mobile Remote — 桌面 GUI 客户端模块
// 在 dsh 设置页注册"连接移动端设备"页：显示供手机 App 扫码连接的二维码。
//
// 打包形态：window.__ModuleLoader__.load({ id, factory })（dsh-client-modules 约定）。
// 手写 React.createElement（无 JSX/构建链），依赖由 dsh 客户端运行时提供。
// 数据来源：GET /m/api/qr-config（仅 loopback 可访问，返回地址+口令）。
//
// 视觉：与官方设置页共用一套令牌与几何——设置卡片 R20 + 0.5px 发丝描边、
// 按钮 sm（H28/R8）、行分隔 0.5px、字体走官方字号阶梯；亮暗只由
// body[data-ds-dark-theme] 切换的 --dsw-alias-* 决定，JS 不判断主题。

window.__ModuleLoader__.load({
	id: "dsh-mobile-remote",
	factory: (require) => {
		var module = { exports: {} };
		var exports = module.exports;

		var react = require("react");
		var jsxRuntime = require("react/jsx-runtime");

		var useState = react.useState;
		var useEffect = react.useEffect;
		var useRef = react.useRef;

		/** 所需服务：slots（设置页 slot 注册）。 */
		exports.inject = ["slots"];

		var QR_CONFIG = "/m/api/qr-config";
		var QR_IMAGE = "/m/qr.png";

		// ── 官方设置页样式（内联对象；颜色/字体只引用 ui-theme 令牌，字面值仅几何） ──

		/** section 列：标题 + 卡片，间距 16。 */
		var sectionStyle = {
			display: "flex",
			flexDirection: "column",
			gap: "16px",
			maxWidth: "720px",
			color: "var(--dsw-alias-label-primary)",
		};

		var headerStyle = { display: "flex", flexDirection: "column", gap: "8px" };

		/** 页标题：官方 --dsw-font-m-18（500 16/28）。 */
		var titleStyle = { margin: 0, font: "var(--dsw-font-m-18)" };

		/** 引导语：14/22 三级文字（设置页 intro 语言）。 */
		var introStyle = {
			margin: 0,
			font: "var(--dsw-font-s-14)",
			color: "var(--dsw-alias-label-tertiary)",
		};

		/** 设置卡片：R20 + 0.5px 发丝描边 + 卡片填充，无投影（docs/ui-radius.md）。 */
		var cardStyle = {
			display: "flex",
			flexDirection: "column",
			padding: "20px",
			border: "0.5px solid var(--dsw-alias-settings-card-stroke)",
			borderRadius: "var(--dsw-radius-xl)",
			background: "var(--dsw-alias-settings-card-fill)",
		};

		/** 二维码区：居中列，图下说明 12/18 三级色。 */
		var qrBlockStyle = {
			display: "flex",
			flexDirection: "column",
			alignItems: "center",
			gap: "12px",
			paddingBottom: "16px",
		};

		/** 二维码承载面：240 方框、内衬 12；底色 layer-1（二维码图片自身白底，不做反色）。 */
		var qrTileStyle = {
			boxSizing: "border-box",
			width: "240px",
			height: "240px",
			padding: "12px",
			borderRadius: "var(--dsw-radius-lg)",
			background: "var(--dsw-alias-bg-layer-1)",
		};

		/** 二维码图：固定 216×216，圆角 lg。 */
		var qrImageStyle = {
			display: "block",
			width: "216px",
			height: "216px",
			borderRadius: "var(--dsw-radius-lg)",
		};

		var qrCaptionStyle = {
			font: "var(--dsw-font-xxs-12)",
			color: "var(--dsw-alias-label-tertiary)",
		};

		/** 连接信息区：与二维码区隔一条 0.5px 分隔线，上下内衬 16。 */
		var infoBlockStyle = {
			display: "flex",
			flexDirection: "column",
			paddingTop: "16px",
			borderTop: "0.5px solid var(--dsw-alias-border-l2)",
		};

		/** 分组标题：13/20 中等字重，次级色。 */
		var infoTitleStyle = {
			margin: "0 0 4px",
			font: "var(--dsw-font-xs-strong-13)",
			color: "var(--dsw-alias-label-secondary)",
		};

		/** 行：左标签 13/20 次级色、右值 13/20 主色 + 复制按钮，0.5px 分隔。 */
		var rowStyle = {
			display: "flex",
			alignItems: "center",
			gap: "12px",
			minHeight: "40px",
			padding: "8px 0",
			borderBottom: "0.5px solid var(--dsw-alias-border-l2)",
		};

		/** 行末行去掉分隔线（官方列的收尾约定）。 */
		var lastRowStyle = Object.assign({}, rowStyle, { borderBottom: "none" });

		var rowLabelStyle = {
			flex: "none",
			width: "64px",
			font: "var(--dsw-font-xs-13)",
			color: "var(--dsw-alias-label-secondary)",
		};

		/** 等宽值（地址、口令）：13/20，官方代码字体栈。 */
		var rowValueStyle = {
			flex: "1 1 auto",
			minWidth: 0,
			fontSize: "13px",
			lineHeight: "20px",
			fontFamily: "var(--ds-font-family-code)",
			color: "var(--dsw-alias-label-primary)",
			wordBreak: "break-all",
		};

		/** 未启用口令时的值：三级文字。 */
		var rowValueMutedStyle = Object.assign({}, rowValueStyle, {
			color: "var(--dsw-alias-label-tertiary)",
		});

		/** 口令未启用告警：warn 三级底 + warn 标签色，12/18，R12。 */
		var warnStyle = {
			margin: 0,
			padding: "12px 16px",
			borderRadius: "var(--dsw-radius-md)",
			background: "var(--dsw-alias-state-warn-tertiary)",
			color: "var(--dsw-alias-state-warn-label)",
			font: "var(--dsw-font-xxs-12)",
		};

		/** 页脚说明：12/18 三级色。 */
		var footnoteStyle = {
			margin: 0,
			font: "var(--dsw-font-xxs-12)",
			color: "var(--dsw-alias-label-tertiary)",
		};

		var loadingStyle = {
			padding: "16px 0",
			font: "var(--dsw-font-s-14)",
			color: "var(--dsw-alias-label-tertiary)",
		};

		/** 取数失败：沿用设置卡片材质，文字取官方错误语义色。 */
		var errorStyle = {
			padding: "16px",
			border: "0.5px solid var(--dsw-alias-settings-card-stroke)",
			borderRadius: "var(--dsw-radius-xl)",
			background: "var(--dsw-alias-settings-card-fill)",
			font: "var(--dsw-font-s-14)",
			color: "var(--dsw-alias-state-error-primary)",
		};

		function fallbackCopy(text) {
			// 非安全上下文（http 局域网 IP）下 Clipboard API 不可用，用 textarea + execCommand 降级
			var ta = document.createElement("textarea");
			ta.value = text;
			ta.style.position = "fixed";
			ta.style.opacity = "0";
			document.body.appendChild(ta);
			ta.select();
			var copied = false;
			try {
				copied = document.execCommand("copy");
			} catch (_) {
				/* 忽略：部分环境直接抛错，按失败提示 */
			}
			ta.remove();
			return copied;
		}

		/**
		 * 复制文本。
		 * @returns Promise<boolean> —— 是否真的写入了剪贴板（复制按钮据此给成功/失败反馈）。
		 */
		function copyText(text) {
			if (navigator.clipboard && window.isSecureContext) {
				return navigator.clipboard.writeText(text).then(
					function () {
						return true;
					},
					function () {
						return fallbackCopy(text);
					}
				);
			}
			return Promise.resolve(fallbackCopy(text));
		}

		/** 复制访问口令：60 秒后自动清空剪贴板（口令是唯一凭据，防其他应用读取；尽力而为）。 */
		function copyToken(token) {
			return copyText(token).then(function (copied) {
				if (!copied) return false;
				setTimeout(function () {
					try {
						if (navigator.clipboard && window.isSecureContext) {
							navigator.clipboard.readText().then(function (t) {
								if (t === token) navigator.clipboard.writeText("");
							});
						}
					} catch (_) {
						/* 非安全上下文等场景尽力而为 */
					}
				}, 60000);
				return true;
			});
		}

		/**
		 * 复制按钮：官方紧凑按钮 sm（H28 / R8 / 0.5px 发丝描边）。
		 * 复制结果用官方状态色短暂提示：成功 --dsw-alias-state-success-primary，
		 * 失败 --dsw-alias-state-error-primary，1.6s 后回到常态。
		 * @param props.onCopy 复制动作，返回 Promise<boolean>（是否成功）。
		 */
		function CopyButton(props) {
			var phaseState = useState("idle");
			var phase = phaseState[0];
			var setPhase = phaseState[1];
			var hoverState = useState(false);
			var hovered = hoverState[0];
			var setHovered = hoverState[1];
			var timer = useRef(0);

			useEffect(function () {
				return function () {
					clearTimeout(timer.current);
				};
			}, []);

			function press() {
				Promise.resolve(props.onCopy()).then(function (copied) {
					setPhase(copied ? "ok" : "err");
					clearTimeout(timer.current);
					timer.current = setTimeout(function () {
						setPhase("idle");
					}, 1600);
				});
			}

			var label = phase === "ok" ? "已复制" : phase === "err" ? "复制失败" : "复制";
			var color =
				phase === "ok"
					? "var(--dsw-alias-state-success-primary)"
					: phase === "err"
						? "var(--dsw-alias-state-error-primary)"
						: "var(--dsw-alias-label-primary)";

			return jsxRuntime.jsx("button", {
				type: "button",
				"aria-live": "polite",
				onClick: press,
				onMouseEnter: function () {
					setHovered(true);
				},
				onMouseLeave: function () {
					setHovered(false);
				},
				style: {
					boxSizing: "border-box",
					flex: "none",
					display: "inline-flex",
					alignItems: "center",
					justifyContent: "center",
					minWidth: "68px",
					height: "28px",
					padding: "0 10px",
					border: "0.5px solid var(--dsw-alias-border-l3)",
					borderRadius: "var(--dsw-radius-sm)",
					background:
						hovered && phase === "idle" ? "var(--dsw-alias-interactive-bg-hover)" : "transparent",
					color: color,
					font: "var(--dsw-font-xxs-12)",
					cursor: "pointer",
					transition:
						"background var(--ds-transition-duration) var(--ds-ease-in-out), color var(--ds-transition-duration) var(--ds-ease-in-out)",
				},
				children: label,
			});
		}

		/** section 外壳：页标题 + 引导语；内容（加载/错误/正常）由调用方给。 */
		function renderSection(children) {
			return jsxRuntime.jsx("div", {
				style: sectionStyle,
				children: [
					jsxRuntime.jsx("div", {
						style: headerStyle,
						children: [
							jsxRuntime.jsx("h2", { style: titleStyle, children: "连接移动端设备" }),
							jsxRuntime.jsx("div", {
								style: introStyle,
								children:
									"用手机 DSH Remote App 扫描下方二维码，自动填入电脑地址与访问口令，即可远程发消息、看进度、收通知、审批决策。",
							}),
						],
					}),
					children,
				],
			});
		}

		/**
		 * 设置页 section：连接移动端设备。
		 * 挂载后从 /m/api/qr-config 拉取地址与口令，渲染二维码 + 连接信息。
		 */
		function MobileDeviceSection() {
			var state = useState({ status: "loading", urls: [], token: "" });
			var data = state[0];
			var setData = state[1];

			useEffect(function () {
				var alive = true;
				fetch(QR_CONFIG, { headers: { accept: "application/json" } })
					.then(function (res) {
						if (!res.ok) throw new Error("HTTP " + res.status);
						return res.json();
					})
					.then(function (body) {
						if (!alive) return;
						var urls = Array.isArray(body.urls) ? body.urls : [];
						// v3.0.0 review：path 从 qr-config 读取（不再硬编码 /m——插件挂载路径可配置）
						setData({ status: "ready", urls: urls, token: String(body.token ?? ""), basePath: String(body.path || "/m") });
					})
					.catch(function (err) {
						if (!alive) return;
						setData({
							status: "error",
							urls: [],
							token: "",
							message: String(err?.message ?? err),
						});
					});
				return function () {
					alive = false;
				};
			}, []);

			if (data.status === "loading") {
				return renderSection(jsxRuntime.jsx("div", { style: loadingStyle, children: "加载中…" }));
			}
			if (data.status === "error") {
				return renderSection(
					jsxRuntime.jsx("div", {
						style: errorStyle,
						children:
							"无法获取连接信息：" + data.message + "（确认 dsh-mobile-remote 插件已启用，且路径为 /m）",
					})
				);
			}

			var primary = data.urls.find(function (u) {
				return !u.includes("127.0.0.1");
			});
			var qrTarget = primary ?? data.urls[0] ?? "http://127.0.0.1:3080";
			// v3.0.0 review：二维码 URL 携带挂载路径（App 端解析后使用，不再写死 /m）
			//
			// 2026-10-19 修复（对齐上游 PR #32 的双重路径部分）：/m/api/qr-config 在
			// LAN 桥模式下返回的地址已经自带挂载路径（http://ip:3082/m），这里若再无
			// 条件拼一次 mount，二维码内容就会变成 …/m/m；App 端 _pathOf() 会把它原样
			// 当作请求前缀，于是扫码连上后所有请求 404。
			// 规则：地址本身已有路径 → 不再拼接；没有路径（旧版服务端）→ 补 mount。
			// 两种形态都正确，且向后兼容。
			var mount = String(data.basePath || "/m").replace(/\/+$/, "");
			var withMount = function (target) {
				try {
					var path = new URL(target).pathname.replace(/\/+$/, "");
					if (path) return target;
				} catch (e) {
					/* 非法 URL：按无路径处理，走拼接兜底 */
				}
				return String(target).replace(/\/+$/, "") + mount;
			};
			var qrPayload = "DSHREMOTE|" + withMount(qrTarget) + "|" + data.token;
			var qrSrc = mount + "/qr.png?text=" + encodeURIComponent(qrPayload);
			var tokenText = data.token
				? data.token.slice(0, 6) + "…" + data.token.slice(-4)
				: "未启用（局域网/内网环境）";

			var rows = data.urls.map(function (u) {
				return jsxRuntime.jsx(
					"div",
					{
						style: rowStyle,
						children: [
							jsxRuntime.jsx("span", { style: rowLabelStyle, children: "地址" }),
							jsxRuntime.jsx("span", { style: rowValueStyle, children: u }),
							jsxRuntime.jsx(CopyButton, {
								onCopy: function () {
									return copyText(u);
								},
							}),
						],
					},
					u
				);
			});
			rows.push(
				jsxRuntime.jsx(
					"div",
					{
						style: lastRowStyle,
						children: [
							jsxRuntime.jsx("span", { style: rowLabelStyle, children: "访问口令" }),
							jsxRuntime.jsx("span", {
								style: data.token ? rowValueStyle : rowValueMutedStyle,
								children: tokenText,
							}),
							data.token
								? jsxRuntime.jsx(CopyButton, {
										onCopy: function () {
											return copyToken(data.token);
										},
									})
								: null,
						],
					},
					"token"
				)
			);

			return renderSection([
				data.token
					? null
					: jsxRuntime.jsx("div", {
							style: warnStyle,
							children:
								"⚠️ 访问口令未启用：同一网络内任何设备都能连接并控制 agent，建议立即在 cordis.patch.yml 配置 authToken 后重启。",
						}),
				jsxRuntime.jsx("div", {
					style: cardStyle,
					children: [
						jsxRuntime.jsx("div", {
							style: qrBlockStyle,
							children: [
								jsxRuntime.jsx("div", {
									style: qrTileStyle,
									children: jsxRuntime.jsx("img", {
										src: qrSrc,
										alt: "连接二维码",
										width: 216,
										height: 216,
										style: qrImageStyle,
									}),
								}),
								jsxRuntime.jsx("div", {
									style: qrCaptionStyle,
									children: "打开 App → 扫码连接 → 对准本二维码",
								}),
							],
						}),
						jsxRuntime.jsx("div", {
							style: infoBlockStyle,
							children: [
								jsxRuntime.jsx("div", { style: infoTitleStyle, children: "连接信息" }),
								rows,
							],
						}),
					],
				}),
				jsxRuntime.jsx("div", {
					style: footnoteStyle,
					children:
						"二维码包含访问口令，仅在本机显示；请勿截屏转发。App 与手机浏览器（/m 网页）共用同一连接。",
				}),
			]);
		}

		/** 注册设置页 section（id: mobile-device）。 */
		function apply(ctx) {
			ctx.slots.inject("settings.section", function () {
				return ctx.slots.register(
					{
						name: "settings.section",
						id: "mobile-device",
						order: 90,
						label: "连接移动端设备",
					},
					MobileDeviceSection
				);
			});
		}
		exports.apply = apply;

		return module.exports;
	},
});
