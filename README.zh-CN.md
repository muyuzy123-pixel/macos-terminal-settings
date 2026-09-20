# 终端设置 · Terminal Settings

[English](README.md)

原生 macOS SwiftUI 应用，将一组经过整理、通常需要终端命令的持久偏好做成图形界面。每项功能都有作用、风险、来源、等价命令和恢复说明。

**开发基线：1.9.0（Build 17）。** 使用 [MIT 许可证](LICENSE)，源码维护于个人账号下的私有仓库 [muyuzy123-pixel/macos-terminal-settings](https://github.com/muyuzy123-pixel/macos-terminal-settings)。仓库保持私有，尚未宣布公开发布。

## 功能

- 40 项设置，覆盖程序坞、访达、截屏、触控板、键盘、窗口、系统与开发、高级电源选项。
- 7 组数值控件、10 个参数，包括 Dock 双尺寸和屏保闲置时间。
- 简体中文与英文即时切换，支持双语搜索。
- 系统当前值与草稿分开显示。数值编辑、预设、载入当前值只改变草稿，明确点击应用后才写入；主功能开关属于执行操作，可能立即写入。
- 组织管理状态检查、精确保留类型的快照、外部修改冲突检查、持久撤销和写前恢复日志。
- 明确区分「删除显式值」「恢复接管前值」「撤销上次操作」。

当前目录包含 34 项「仅终端」、4 项「系统设置增强」、2 项「系统设置镜像」。这一分类只代表已核对版本；未公开偏好可能随系统升级变化。写入后读回成功只证明存储值正确，不保证实际界面效果。

## 系统与构建

需要 Apple 芯片 Mac、提供 **macOS 26.x SDK** 的 Xcode 或 Apple Command Line Tools。最低部署版本为 macOS 14，继承的实机验收环境为 macOS 26.6.2；尚未完成真实 macOS 14 运行验收。不提供 Intel 二进制。无包管理器或第三方运行时依赖。

```sh
zsh verify.sh --contract-only
zsh build.sh
zsh scripts/check-release.sh
```

生成 `TerminalSettings.app`、`TerminalSettings.zip`，独立解包核验结果保存在 `dist/`。支持包含空格的源码路径。可使用 `DEVELOPER_DIR`、`SDKROOT` 显式指定工具链；默认优先已安装的 Command Line Tools。

当前产物使用 Hardened Runtime 的 **ad-hoc 签名**，未使用 Developer ID，未经过 Apple 公证。下载后可能被系统拦截，不宣称可直接通过 Gatekeeper，也不建议关闭系统安全机制。

## 权限与本地数据

普通功能只操作当前用户偏好，部分使用当前主机作用域。高级功能在执行时请求管理员授权，仅允许 `ttyskeepawake`、`proximitywake`、`acwake` 三个 `pmset` 布尔键。

应用不请求辅助功能、屏幕录制、自动化、完全磁盘访问或输入监控。源码中没有遥测、自动更新或网络客户端；参考链接由系统浏览器打开。语言、草稿和逐项接管前恢复基线保存在应用偏好中；上次撤销文件和待恢复事务日志保存在本机 Application Support。继续使用 `com.codex.TerminalSettings` Bundle ID 以兼容已有记录。

高级权限桥仍调用 Apple 已弃用的 `AuthorizationExecuteWithPrivileges`。这部分沿用开发基线，迁移现代签名 helper 是后续工作。详见 [安全边界](SECURITY.md)。

## 参与开发与发布

参见 [贡献约定](CONTRIBUTING.md)、[测试说明](docs/TESTING.md)、[发布流程](docs/RELEASING.md)。历史 QA 原始数据、机器状态快照、旧制品和一次性翻译迁移脚本不进入公开仓库。

[基线哈希](docs/upstream-baseline.json) 记录整理前导入文件，[来源说明](docs/ATTRIBUTION.md) 说明功能目录的参考资料。
