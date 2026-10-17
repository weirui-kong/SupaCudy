# Product rules

## Positioning

- For people who do not want to tinker with OpenWrt: common tasks (internet, repeater, VPN, Wi-Fi, clients) take a few taps.
- LuCI stays installed as the "advanced settings" escape hatch. SupaCudy covers frequent tasks, not every OpenWrt option.
- We learn from the **interaction design and feature layout** of similar products, but never copy any vendor's code, icons, logos, illustrations or copy.

## Desktop and mobile

- Every page must be usable on a phone in portrait (width ≥ 360px) and on a wide desktop screen (width ≥ 1280px).
- Mobile: single column, primary actions within thumb reach, touch targets at least 44×44px, no horizontal scrolling.
- Desktop: use the width (multiple columns or side navigation); do not just stretch the phone layout.
- Widths in between must transition smoothly with no broken layouts.

## Languages

- Only Simplified Chinese (zh-CN) and English (en).
- On first visit, pick the language from the browser; anything else falls back to English. Users can switch manually and the choice is remembered.
- All UI text goes through i18n keys. Both languages must always have the full set of keys; a raw key must never be shown.
- Chinese uses standard written Simplified Chinese; English uses concise sentence case, except navigation sections and page titles, which use title case ("Port Forwarding", "Ad Blocking"). Terms stay consistent with the glossary below.

## Light and dark mode

- Follow the system `prefers-color-scheme` by default, with a manual "System / Light / Dark" switch whose choice is remembered.
- Text contrast meets WCAG AA (4.5:1 for body text) in both modes.
- Icons, charts and status colors must be clear in both modes, and status is never conveyed by color alone (pair it with an icon or text).

## Interaction principles

- **One page, one task.** Show the most common options first; fold advanced options away.
- **Defaults must just work.** A user who changes nothing still gets a safe, working setup.
- **Every change gives feedback.** Show "Applying" after submit, then a clear success or failure; failures say why and what to do next.
- **Warn before anything that drops the connection**, e.g. changing the LAN address, the operating mode or the Wi-Fi password: say the current connection will drop and how to reconnect.
- **Confirm dangerous actions.** Factory reset, firmware upgrade and deleting configuration need a confirmation that states the consequences.
- **No fake data.** Values that cannot be read show "—" or an explicit error state, never placeholder numbers.

## Accounts

- **One password for everything with a login** (Unified Password): SSH, the web UI, AdGuard Home's own page and any login added later all use user `root` with the admin password. Wi-Fi and VPN credentials are separate.
- Factory login: user `root`, password `supacudy`. The login page shows it only until setup is done, and the setup wizard requires a new password (the factory one is refused).
- **Login protection** is on by default: an address with 3 failed logins (any of them) within 30 minutes cannot reach the management services for 120 minutes, while its internet access keeps working. The web UI logs in through `/cgi-bin/supacudy-login`, never through anonymous `session.login` on `/ubus`, so every failure is counted with the caller's address.
- Changing the admin password in SupaCudy updates every login at once. A change made outside SupaCudy (`passwd`, LuCI) is detected, and the UI asks for the password once to bring the others in line.

## Glossary

| English | 中文 | Meaning |
|---|---|---|
| Repeater | 中继 | The router gets internet from an upstream Wi-Fi network |
| Tethering | 手机共享网络 | Using a phone's connection over USB |
| Ethernet WAN | 有线 WAN | |
| Clients | 客户端 | Devices connected to the router |
| Admin password | 管理密码 | Password of the root user, shared by every login (SSH, web UI, AdGuard Home) |
