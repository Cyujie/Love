# 两个人的小日子

一个适配手机和电脑的情侣空间网页，使用 Supabase 管理账号与共享数据。

## 网页里已有的功能

- 邮箱注册、登录、邮箱验证和密码重置
- 通过邀请码创建/加入两人空间，并设置恋爱开始日
- 恋爱天数和周年倒计时
- 纪念日、生日、旅行等重要日期记录
- 仅配对成员可看的照片与文字回忆
- 每日心情打卡
- 共同愿望清单，支持记录进度和标记完成（最多 100 项）
- 爱情树浇水、虚拟宠物喂养/陪玩、农场合作互动记录
- 早安/晚安提醒的时区和时间偏好
- 线下房间布置建议与两人共享的待办清单
- 双方主动授权后可共享实时位置：只保留每人最新坐标，不记录轨迹；停止共享会删除坐标，伴侣只能看到最近 2 分钟内更新的位置

爱情树、宠物和农场目前以双方共同互动、累计记录为主，后续可以继续扩展成任务、成长和小游戏系统。

## Supabase 项目配置

网页已连接到 Supabase 项目 `Love`（新加坡区域），项目 URL 和 Publishable key 已写入 `config.js`。所需表、RLS 策略、配对 RPC、私有照片 bucket，以及房间方案和位置共享表均已在该项目建立；无需再次执行 SQL。完整初始化脚本和新增迁移保存在 `supabase/` 目录。

部署到 GitHub Pages 后，网页地址为 `https://cyujie.github.io/Love/`。仓库的 `.github/workflows/pages.yml` 会在推送到 `main` 时自动发布。首次发布前，在仓库 **Settings → Pages → Build and deployment → Source** 选择 **GitHub Actions**。

还需在 Supabase Dashboard 的 **Authentication → URL Configuration** 中，将 `https://cyujie.github.io/**` 加入 Redirect URLs，并将 `https://cyujie.github.io/Love/` 设为 Site URL；本地预览时可额外添加 `http://localhost:8000/**`。邮箱验证链接会跳回网站。

在 `outputs` 目录运行 `python -m http.server 8000`，然后打开 `http://localhost:8000`。`config.js` 使用的是浏览器可用的 Publishable key；不要替换成 `service_role` 或 secret key，也不要把 secret key 发布到网页或 GitHub。

当前 Supabase 项目已关闭邮箱验证，注册成功后即可登录。登录后任一方创建空间并分享 8 位邀请码；另一方注册并登录后输入邀请码加入。

## 目前范围

- 纪念日可记录，首页会计算恋爱天数和下一个周年倒计时；自动邮件/推送提醒还需要单独部署定时通知服务。
- 提醒页面保存早安/晚安时间和双方时区偏好，但不会自行向手机发送通知。
- 私密相册使用 Supabase 私有 Storage bucket 与 RLS，只允许配对成员访问。单张图片限制 8 MB，接受 JPEG、PNG、WebP、GIF。
- 农场是合作互动记录原型，还没有完整的种植、成熟周期、道具和金币经济系统。
- 实时定位只在双方各自勾选同意、点击开启并允许浏览器定位后运行；网页关闭会停止更新，超过 2 分钟的位置会对伴侣隐藏。重新登录后可点击停止并清除本人留存的最新坐标。不会记录位置轨迹。

## 安全

- Supabase Auth 管理邮箱和密码，网页不保存密码。
- 不把任何 service role/secret key 放进网页。
- 所有公开 schema 表启用 RLS；照片使用私有 bucket 和成员策略。
- 创建空间、邀请码配对和恋爱开始日设置都由受限 RPC 校验当前登录账号与空间成员身份。


