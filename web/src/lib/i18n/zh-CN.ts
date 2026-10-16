// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import type { MessageShape } from './types';
import type en from './en';

const zhCN: MessageShape<typeof en> = {
  app: {
    name: 'SupaCudy',
    skip_to_content: '跳到主要内容',
  },
  nav: {
    main: '主导航',
    overview: '概览',
    settings: '设置',
    logout: '退出登录',
  },
  login: {
    title: '登录',
    subtitle: '输入管理密码来管理你的路由器。',
    password: '管理密码',
    show_password: '显示密码',
    hide_password: '隐藏密码',
    submit: '登录',
    submitting: '正在登录…',
    wrong_password: '密码错误，请重试。',
  },
  overview: {
    title: '概览',
    device: '设备',
    model: '型号',
    board: '板型',
    openwrt: 'OpenWrt',
    supacudy: 'SupaCudy',
    system: '系统',
    uptime: '运行时间',
    load: '平均负载',
    load_hint: '过去 1、5、15 分钟里等待 CPU 的平均进程数。超过 CPU 核心数说明路由器比较忙。',
    load_value: '{one} / {five} / {fifteen}',
    cpus: 'CPU 核心数',
    memory: '内存',
    memory_value: '已用 {used}，共 {total}',
    memory_hint: '这里是 Linux 可用的内存。一部分物理内存预留给了 Wi-Fi，所以总量比硬件规格小。',
    refresh_failed: '状态刷新失败，正在自动重试。',
  },
  settings: {
    title: '设置',
    appearance: '外观',
    language: '语言',
    theme: '主题',
    theme_system: '跟随系统',
    theme_light: '亮色',
    theme_dark: '暗色',
    session: '会话',
    logout_hint: '在这个浏览器上退出管理面板。',
  },
  time: {
    minutes: '{m} 分钟',
    hours_minutes: '{h} 小时 {m} 分钟',
    days_hours: '{d} 天 {h} 小时',
  },
  common: {
    unavailable: '—',
    more_info: '更多说明',
    close: '关闭',
    loading: '正在加载…',
  },
  errors: {
    network: '无法连接路由器，请检查网络后重试。',
    denied: '登录已过期，请重新登录。',
    unknown: '出错了（错误码 {code}），请重试。',
  },
  languages: {
    en: 'English',
    'zh-CN': '简体中文',
  },
};

export default zhCN;
