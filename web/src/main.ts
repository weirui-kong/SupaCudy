// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

import { mount } from 'svelte';
import App from './App.svelte';
import './styles/tokens.css';
import './styles/base.css';

mount(App, { target: document.getElementById('app')! });
