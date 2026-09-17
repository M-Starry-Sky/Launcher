# Starry Sky Launcher / 星穹次元启动器

**English** | [中文](#中文说明)

Personal, open-source, **third-party** Windows desktop helper for *Minecraft*:

- **Java Edition** — download / instance management, official MSA login, launch
- **Bedrock Edition** — detect Microsoft Store install, apply local options & packs, launch / friend rooms

This repository publishes **client (Flutter) source only**.

| Item | Value |
|------|--------|
| Product | Starry Sky Launcher (星穹次元启动器) |
| Editions | Java Edition + Bedrock Edition (Windows) |
| Version | See `pubspec.yaml` / `version.json` (keep in sync) |
| License | [Apache-2.0](./LICENSE) |
| Repository | https://github.com/M-Starry-Sky/Launcher |
| Publisher | M-Starry-Sky / 星夜幻梦 |
| Contact | QQ `2569966922` |

---

## Supported editions

### Java Edition

- Sign in with a **personal Microsoft account (MSA)** via **Azure AD device code** (your Entra app GUID) **or** the **Xbox Live public client** (`00000000402b5328` on `login.live.com`).
- Complete **Xbox Live → XSTS → Minecraft Services** for legitimate ownership / session.
- Download vanilla files from **official Mojang / Microsoft endpoints** (optional user-chosen mirrors).
- Manage local instances, Java runtime, mods, and launch options.

### Bedrock Edition (Windows)

- Detect a **legally installed** Minecraft Bedrock from the **Microsoft Store** (this launcher does **not** redistribute or host the Bedrock game binary).
- Apply local render / options presets and sync **resource packs / behavior packs** into the user’s `com.mojang` data folders.
- Launch the installed Bedrock client and assist **friend rooms** (user tunnel and/or platform room info when enabled).
- Bedrock online play still relies on the user’s Microsoft / Xbox account as provided by the official game client.

---

## Purpose (for Microsoft identity / Xbox Live app review)

This application is a **legitimate Minecraft launcher assistant** for both Java and Bedrock on Windows. It helps players:

1. Sign in with a **personal Microsoft account** (MSA): **Azure AD v2 device code** against `login.microsoftonline.com` (consumers) when an Entra **application (client) ID** is configured; otherwise the **Xbox Live public client** `00000000402b5328` via `login.live.com` browser authorization code. Both paths are for **Java Edition** session acquisition.
2. Complete the standard **Xbox Live → XSTS → Minecraft Services** ownership check for **Java Edition**.
3. For **Bedrock Edition**, launch the **Microsoft Store–installed** game the user already owns; we do not replace Store licensing or ship Bedrock game packages.
4. Download **Java** vanilla game files from official endpoints (and optional public mirrors chosen by the user).
5. Manage local instances / packs and optional friend rooms via **user-configured** network tunnels.

### Microsoft APIs we use (and why)

| API / endpoint family | Scope / use | Why it is required |
|----------------------|-------------|--------------------|
| `login.microsoftonline.com/.../devicecode` & `.../token` | `XboxLive.signin` `offline_access` | Used when an Azure public-client GUID is configured |
| `login.live.com/oauth20_authorize.srf` & `oauth20_token.srf` | `service::user.auth.xboxlive.com::MBI_SSL` | Used with Xbox Live public client `00000000402b5328` (empty Client ID defaults here) |
| Xbox Live / XSTS | Derive game session credentials | Required by **Minecraft Java** authentication chain |
| Minecraft Services | Profile / ownership | Launch **Java Edition** with a valid session |
| Microsoft Store install (local) | Detect / start Bedrock | Launch **Bedrock** the user already installed; no Store API key required for local package launch |

We do **not**:

- Request password entry inside the launcher UI for Microsoft accounts (device code + browser only).
- Store Microsoft passwords.
- Bypass purchase / ownership / Store licensing checks.
- Crack, pirate, or redistribute Minecraft **Java or Bedrock** game binaries as our product.
- Impersonate the official Minecraft Launcher / Minecraft Bedrock brands.

Azure / Entra app registration notes for reviewers:

- **Platform**: Public client / native. Azure path uses device code; Live public-client path uses `https://login.live.com/oauth20_desktop.srf`.
- **Account type**: Personal Microsoft accounts (consumers).
- **Publisher verification / branding**: Product name **Starry Sky Launcher**; not affiliated with Mojang Studios or Microsoft.
- **Editions**: Supports assisting both **Java Edition** and **Bedrock Edition (Windows Store)** under the same product identity.

---

## Features

- Microsoft account login for Java: Azure device code **or** Xbox Live public client (`00000000402b5328`); Bedrock uses the installed Store client’s own Microsoft/Xbox sign-in.
- Optional third-party auth the user configures themselves (where applicable).
- **Java**: local instance / version management, Java runtime detection, launch options, mod helpers (e.g. public Modrinth API when chosen).
- **Bedrock**: Store install detection, options presets, resource/behavior pack sync, launch, friend-room assist.
- Optional multiplayer assist: users may fill their own tunnel client settings; Microsoft-authenticated users may use platform-assisted room info when available (Java and/or Bedrock room types as enabled).
- In-app update check against this GitHub repository (`version.json`, then Releases API).

---

## Privacy (short)

| Data | Handling |
|------|----------|
| Microsoft tokens (Java MSA path) | Stored locally with OS secure storage / app prefs as needed for refresh; used only for Xbox / Minecraft Java auth chain |
| Bedrock paths / options | Local device only (Store install + `com.mojang` data) |
| Launcher settings | Local device only |
| Optional account profile fields | Shown for launch; not sold |
| Crash / diagnostic | Local logs unless the user voluntarily shares them |

We do not sell personal data. Network calls to Microsoft are governed by [Microsoft Services Agreement](https://www.microsoft.com/servicesagreement) and Minecraft EULA.

---

## Compliance & trademarks

- **Not an official Minecraft product.** Minecraft, Minecraft: Java Edition, and Minecraft (Bedrock) are trademarks of Mojang Synergies AB / Microsoft.
- Users must own a legal copy of the edition they play (Java purchase and/or Bedrock via Microsoft Store, as applicable).
- Users must comply with the [Minecraft EULA](https://www.minecraft.net/eula) and Microsoft terms.
- Apache-2.0 covers **this launcher’s source**; it does not grant Minecraft content rights or Store package redistribution rights.

---

## Build (developers)

```bash
# Flutter stable, Windows desktop
flutter pub get
flutter run -d windows
```

Optional compile-time override for the optional companion service host:

```bash
flutter run -d windows --dart-define=BACKEND_BASE_URL=https://example.invalid
```

Sensitive companion endpoints in source are **sealed** (not plaintext) so casual scraping of the public tree does not expose connection strings.

---

## Versioning & updates

| File | Role |
|------|------|
| `pubspec.yaml` | Flutter package version |
| `lib/core/update/app_version.dart` | In-app constant |
| `version.json` | GitHub raw manifest for update check |

Bump all three together when cutting a release. Optional: attach installers under GitHub Releases.

---

## Security disclosure

If you find a vulnerability in this client, contact the publisher via the QQ above or open a private security advisory on GitHub when available. Please do not file public issues that include exploit details until a fix is ready.

---

<a id="中文说明"></a>

# 中文说明

**个人、开源、第三方** Windows 桌面辅助启动器，同时支持：

- **《我的世界：Java 版》** — 下载 / 实例管理、官方 MSA 登录、启动
- **《我的世界》基岩版** — 检测微软商店安装、写入本机选项与资源包、启动 / 好友房间

本仓库**仅发布客户端（Flutter）源码**。

| 项目 | 内容 |
|------|------|
| 产品名 | 星穹次元启动器（Starry Sky Launcher） |
| 支持版本 | Java 版 + 基岩版（Windows） |
| 版本号 | 以 `pubspec.yaml` / `version.json` 为准（三者需同步） |
| 许可 | [Apache-2.0](./LICENSE) |
| 仓库 | https://github.com/M-Starry-Sky/Launcher |
| 发行方 | M-Starry-Sky / 星夜幻梦 |
| 联系 | QQ `2569966922` |

---

## 支持的版本线

### Java 版

- 通过 **Azure 设备码**（自建应用 GUID）或 **Xbox Live 公共客户端** `00000000402b5328`（`login.live.com` 浏览器授权）使用**个人微软账号（MSA）**登录。
- 完成 **Xbox Live → XSTS → Minecraft Services**，获取合法会话 / 正版拥有状态。
- 从 **Mojang / Microsoft 官方端点**（及用户自选公开镜像）下载原版文件。
- 管理本机实例、Java 运行时、模组与启动参数。

### 基岩版（Windows）

- 检测用户已通过**微软商店合法安装**的基岩版（本启动器**不托管、不分发**基岩版游戏本体）。
- 写入本机渲染 / 选项预设，并将**资源包 / 行为包**同步到用户 `com.mojang` 数据目录。
- 启动已安装的基岩客户端，并辅助**好友联机房间**（用户自配隧道和/或平台房间信息，视开关而定）。
- 基岩在线玩法仍由官方客户端内的微软 / Xbox 账号体系完成。

---

## 用途说明（供微软身份平台 / Xbox Live 应用审核）

本软件是面向 **Java 版与基岩版** 的**正规启动辅助工具**，用于帮助玩家：

1. 通过**个人微软账号（MSA）**登录：配置了 Azure 应用 GUID 时走 `login.microsoftonline.com` **设备码**；未填或填写 `00000000402b5328` 时走 `login.live.com` **Xbox Live 公共客户端授权码**——用于获取 **Java 版**会话。
2. 按官方链路完成 **Xbox Live → XSTS → Minecraft Services**，校验 **Java 版**正版拥有状态。
3. 对 **基岩版**：启动用户已在**微软商店安装并拥有**的客户端；我们不替代商店授权，也不分发基岩版安装包。
4. 从官方端点下载 **Java 版**原版游戏文件（及用户自选公开镜像）。
5. 管理本机实例 / 整合包，以及可选的好友联机（用户可自配隧道客户端）。

### 使用的微软相关接口（及原因）

| 接口族 | 权限 / 用途 | 必要性 |
|--------|-------------|--------|
| 设备码与令牌端点 | `XboxLive.signin`、`offline_access` | 填写 Azure GUID 时使用 |
| Live 授权码与换票 | `service::user.auth.xboxlive.com::MBI_SSL` | 公共客户端 `00000000402b5328`（Client ID 为空时默认） |
| Xbox Live / XSTS | 派生游戏会话凭据 | **Java 版**认证链必需 |
| Minecraft Services | 档案 / 拥有状态 | 以合法会话启动 **Java 版** |
| 本机微软商店安装检测 / 启动 | 定位并启动基岩版 | 启动用户已安装的 **基岩版**；本地启动无需 Store API 密钥 |

我们**不会**：

- 在启动器内要求用户输入微软账号密码（仅设备码 + 浏览器）；
- 存储微软密码；
- 绕过购买 / 正版 / 商店授权校验；
- 以破解、盗版方式分发 **Java 或基岩**游戏本体作为产品；
- 冒充官方 Minecraft Launcher / 基岩版品牌。

审核备注：

- **客户端类型**：公共客户端 / 原生（Azure 设备码，或 Live `oauth20_desktop.srf` 回调）；
- **品牌**：星穹次元启动器；与 Mojang / Microsoft **无隶属关系**；
- **版本线**：同一产品身份下辅助 **Java 版**与 **基岩版（Windows 商店）**。

---

## 功能概要

- 微软账号登录用于 Java（Azure 设备码或 Xbox Live 公共客户端）；基岩版沿用商店客户端自身的微软 / Xbox 登录。
- 可选用户自配的第三方登录（在适用场景下）。
- **Java**：实例与版本管理、Java 检测、启动参数、模组辅助（如用户选择时的公开 Modrinth API）。
- **基岩**：商店安装检测、选项预设、资源包 / 行为包同步、启动、好友房间辅助。
- 可选联机辅助：用户可填写自有隧道；正版账号在可用时可使用平台房间信息（Java / 基岩房间类型视开关而定）。
- 通过本 GitHub 仓库做版本校验（优先 `version.json`，其次 Releases API）。

---

## 隐私（摘要）

| 数据 | 处理方式 |
|------|----------|
| 微软令牌（Java MSA 路径） | 仅存本机安全存储 / 应用配置，用于 Xbox / Minecraft Java 认证链 |
| 基岩路径 / 选项 | 仅本机（商店安装与 `com.mojang` 数据） |
| 启动器设置 | 仅本机 |
| 档案展示信息 | 仅用于启动展示，不出售 |
| 诊断日志 | 默认本机；用户自愿提供时才外传 |

不出售个人数据。访问微软服务须遵守微软服务协议与 Minecraft EULA。

---

## 合规与商标

- **非官方** Minecraft 产品。Minecraft、《我的世界：Java 版》、基岩版均为 Mojang Synergies AB / Microsoft 商标。
- 用户须合法拥有其所游玩的版本（Java 购买和/或微软商店基岩版，视情况而定）。
- 用户须遵守 [Minecraft EULA](https://www.minecraft.net/eula) 与微软条款。
- Apache-2.0 仅覆盖**本启动器源码**，不授予游戏内容权利或商店安装包再分发权利。

---

## 开发构建

```bash
flutter pub get
flutter run -d windows
```

可选编译期覆盖配套服务主机：

```bash
flutter run -d windows --dart-define=BACKEND_BASE_URL=https://example.invalid
```

源码中配套服务入口与业务路由以**密封载荷**存放，避免公开仓库被轻易抓取明文连接串。

---

## 版本与更新

| 文件 | 作用 |
|------|------|
| `pubspec.yaml` | Flutter 包版本 |
| `lib/core/update/app_version.dart` | 应用内常量 |
| `version.json` | GitHub raw 清单 |

发版时请三者一并递增。可选在 GitHub Releases 上传安装包。

---

## 安全披露

如发现客户端安全问题，请通过上方 QQ 联系，或在 GitHub 提供私密安全通告渠道时使用该渠道。在修复前请勿公开可利用细节。
