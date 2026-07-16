import { createServerClient } from '@supabase/ssr'
import { NextResponse, type NextRequest } from 'next/server'

// Next.js 16 で middleware から proxy に改名された(機能は同じ)。
// 役割は2つ:
//   1. 未ログインを /login へ弾く(門前払い)
//   2. 期限が近いセッションを更新する(Server Component は Cookie を書けないため)
// 本当の権限チェックはここではなく Supabase の RLS が担う。
export async function proxy(request: NextRequest) {
  let response = NextResponse.next({ request })

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll()
        },
        setAll(cookiesToSet, headers) {
          cookiesToSet.forEach(({ name, value }) =>
            request.cookies.set(name, value)
          )
          response = NextResponse.next({ request })
          cookiesToSet.forEach(({ name, value, options }) =>
            response.cookies.set(name, value, options)
          )
          // 認証Cookieを含む応答をCDN等にキャッシュさせないためのヘッダ
          Object.entries(headers).forEach(([key, value]) =>
            response.headers.set(key, value)
          )
        },
      },
    }
  )

  // getSession() は Cookie を検証せず信じるためサーバー側では使わない。
  // getClaims() は JWT を検証し、期限が近ければセッションも更新する。
  const { data } = await supabase.auth.getClaims()
  const isSignedIn = data !== null

  const { pathname } = request.nextUrl
  const isLoginPage = pathname.startsWith('/login')

  // 更新済みのセッションCookieを引き継いだままリダイレクトする
  const redirectTo = (destination: string) => {
    const url = request.nextUrl.clone()
    url.pathname = destination
    url.search = ''
    const redirect = NextResponse.redirect(url)
    response.cookies.getAll().forEach((cookie) => redirect.cookies.set(cookie))
    return redirect
  }

  if (!isSignedIn && !isLoginPage) {
    return redirectTo('/login')
  }

  if (isSignedIn && isLoginPage) {
    return redirectTo('/')
  }

  return response
}

export const config = {
  // 静的ファイルと画像は認証チェックの対象外(毎回走らせると無駄)
  matcher: [
    '/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)',
  ],
}
