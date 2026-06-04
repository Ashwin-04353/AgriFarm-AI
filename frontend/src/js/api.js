const BASE = "http://localhost:8000"
let token = localStorage.getItem("agri_token")

export async function apiFetch(endpoint, options = {}) {
  const headers = {
    "Content-Type": "application/json",
    ...(token ? { Authorization: `Bearer ${token}` } : {}),
    ...options.headers
  }
  const res = await fetch(`${BASE}${endpoint}`,
    { ...options, headers, credentials: "include" })

  if (res.status === 401) {
    localStorage.removeItem("agri_token")
    window.location.href = "login.html"
    return
  }
  if (!res.ok) {
    const err = await res.json().catch(() => ({ detail: "Unknown error" }))
    throw new Error(err.detail || "Request failed")
  }
  return res.json()
}

export function setToken(t) {
  token = t
  localStorage.setItem("agri_token", t)
}

export function clearToken() {
  token = null
  localStorage.removeItem("agri_token")
}

export function isLoggedIn() {
  return !!localStorage.getItem("agri_token")
}