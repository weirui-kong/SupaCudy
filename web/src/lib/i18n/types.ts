// Copyright 2026 SupaCudy contributors
// SPDX-License-Identifier: Apache-2.0

// Same keys as T with every leaf widened to string, so a translation can
// neither miss nor add a key without a type error.
export type MessageShape<T> = {
  [K in keyof T]: T[K] extends string ? string : MessageShape<T[K]>;
};

type Join<K extends string, P extends string> = `${K}.${P}`;

export type MessageKey<T> = {
  [K in keyof T & string]: T[K] extends string ? K : Join<K, MessageKey<T[K]>>;
}[keyof T & string];
