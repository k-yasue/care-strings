'use client'

import { useActionState } from 'react'
import { login, type LoginState } from '@/app/actions/auth'

// 文言は後でi18n辞書へ移す想定のため1箇所にまとめる
const t = {
  appName: 'CareStrings',
  lead: '施設アカウントでログインしてください',
  email: 'メールアドレス',
  password: 'パスワード',
  submit: 'ログイン',
  submitting: 'ログイン中…',
  // サインアップ導線は作らない(アカウントは管理者が招待発行する方針)
  note: 'アカウントは施設の管理者が発行します',
} as const

const initialState: LoginState = { error: null }

export default function LoginPage() {
  const [state, formAction, pending] = useActionState(login, initialState)

  return (
    <main className="flex flex-1 items-center justify-center p-6">
      <div className="w-full max-w-sm">
        <h1 className="text-2xl font-bold">{t.appName}</h1>
        <p className="mt-1 text-sm opacity-70">{t.lead}</p>

        <form action={formAction} className="mt-8 flex flex-col gap-4">
          <label className="flex flex-col gap-1">
            <span className="text-sm font-medium">{t.email}</span>
            <input
              type="email"
              name="email"
              required
              autoComplete="email"
              className="rounded-md border border-black/20 px-3 py-2 dark:border-white/20"
            />
          </label>

          <label className="flex flex-col gap-1">
            <span className="text-sm font-medium">{t.password}</span>
            <input
              type="password"
              name="password"
              required
              autoComplete="current-password"
              className="rounded-md border border-black/20 px-3 py-2 dark:border-white/20"
            />
          </label>

          {state.error && (
            <p role="alert" className="text-sm text-red-600 dark:text-red-400">
              {state.error}
            </p>
          )}

          <button
            type="submit"
            disabled={pending}
            className="mt-2 rounded-md bg-foreground px-4 py-2 font-medium text-background disabled:opacity-50"
          >
            {pending ? t.submitting : t.submit}
          </button>
        </form>

        <p className="mt-6 text-xs opacity-60">{t.note}</p>
      </div>
    </main>
  )
}
