/* zyvo web UI - minimal ChatGPT-style client for the local opencode server */
(() => {
  const $ = (id) => document.getElementById(id)
  const log = $("log"), input = $("input"), send = $("send"), sessSel = $("session"), modelEl = $("model")

  let sessionID = null
  let busy = false
  let lastCount = 0
  let lastTextLen = 0
  let stable = 0

  const esc = (t) => {
    const d = document.createElement("div")
    d.textContent = t ?? ""
    return d.innerHTML
  }

  const add = (cls, text) => {
    const div = document.createElement("div")
    div.className = "msg " + cls
    div.innerHTML = esc(text)
    log.appendChild(div)
    log.scrollTop = log.scrollHeight
    return div
  }

  async function api(path, opts) {
    const r = await fetch(path, {
      headers: { "content-type": "application/json" },
      ...opts,
    })
    if (!r.ok) throw new Error(`HTTP ${r.status}: ${(await r.text()).slice(0, 200)}`)
    const ct = r.headers.get("content-type") || ""
    return ct.includes("json") ? r.json() : r.text()
  }

  async function loadSessions() {
    try {
      const list = await api("/session")
      sessSel.innerHTML = ""
      for (const s of list) {
        const o = document.createElement("option")
        o.value = s.id
        o.textContent = s.title || s.id.slice(0, 12)
        sessSel.appendChild(o)
      }
      if (sessionID) sessSel.value = sessionID
    } catch (e) {
      add("sys", "Could not load sessions: " + e.message)
    }
  }

  async function newChat() {
    try {
      const s = await api("/session", { method: "POST", body: JSON.stringify({}) })
      sessionID = s.id
      await loadSessions()
      sessSel.value = sessionID
      log.innerHTML = ""
      add("sys", "New chat started. Ask anything!")
      input.focus()
    } catch (e) {
      add("sys err", "New chat failed: " + e.message)
    }
  }

  async function openSession(id) {
    sessionID = id
    log.innerHTML = ""
    await renderMessages()
  }

  async function renderMessages() {
    if (!sessionID) return
    const msgs = await api(`/session/${sessionID}/message`)
    log.innerHTML = ""
    lastCount = msgs.length
    for (const m of msgs) {
      const text = (m.parts || [])
        .filter((p) => p.type === "text" && p.text)
        .map((p) => p.text)
        .join("\n")
      if (text) add(m.role === "user" ? "user" : "assistant", text)
    }
  }

  function textFromParts(parts) {
    return (parts || [])
      .filter((p) => p.type === "text" && p.text)
      .map((p) => p.text)
      .join("\n")
  }

  async function pollReply() {
    // poll messages until the assistant reply stops growing
    let replyEl = add("assistant", "...")
    let prev = -1
    stable = 0
    while (stable < 3) {
      await new Promise((r) => setTimeout(r, 1200))
      try {
        const msgs = await api(`/session/${sessionID}/message`)
        const assistant = [...msgs].reverse().find((m) => m.role === "assistant")
        const text = assistant ? textFromParts(assistant.parts) : ""
        if (text && text.length === prev) stable++
        else stable = 0
        prev = text.length
        if (text) replyEl.innerHTML = esc(text)
        log.scrollTop = log.scrollHeight
        const statuses = await api("/session/status").catch(() => null)
        const st = statuses && statuses[sessionID]
        if (st && st.busy === false && text) stable = 3
      } catch (e) {
        stable++
      }
    }
  }

  async function sendMsg() {
    const text = input.value.trim()
    if (!text || busy) return
    busy = true
    send.disabled = true
    input.value = ""
    if (!sessionID) await newChat()
    if (!sessionID) { busy = false; send.disabled = false; return }
    add("user", text)
    try {
      await api(`/session/${sessionID}/prompt_async`, {
        method: "POST",
        body: JSON.stringify({ prompt: { text } }),
      })
      await pollReply()
    } catch (e) {
      add("msg sys err", "Send failed: " + e.message)
    }
    busy = false
    send.disabled = false
    input.focus()
    loadSessions()
  }

  async function init() {
    try {
      const cfg = await api("/config")
      modelEl.textContent = cfg.model || ""
    } catch {}
    await loadSessions()
    const list = JSON.parse(JSON.stringify([]))
    try {
      const list2 = await api("/session")
      if (list2.length) {
        sessionID = list2[0].id
        sessSel.value = sessionID
        await renderMessages()
      } else {
        add("sys", "Welcome to zyvo! Type a message to start a new chat.")
      }
    } catch (e) {
      add("sys err", "Init failed: " + e.message)
    }
  }

  send.onclick = sendMsg
  $("new").onclick = newChat
  sessSel.onchange = () => openSession(sessSel.value)
  input.addEventListener("keydown", (e) => {
    if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); sendMsg() }
  })
  input.addEventListener("input", () => {
    input.style.height = "auto"
    input.style.height = Math.min(input.scrollHeight, 140) + "px"
  })
  init()
})()
