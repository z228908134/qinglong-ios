/* iOS 原生壳：在页面脚本跑之前注入。
 *
 * 为什么要有这一段（关键，别删）：
 *   青龙的 CORS 是坏的 —— back/config/index.ts 里 cors.origin 默认是 ['*']（**数组**），
 *   而 cors 包只对字符串 '*' 放行，数组里的 '*' 不会生效。实测面板的预检（OPTIONS）
 *   只回 Access-Control-Allow-Methods / -Headers，不回 Access-Control-Allow-Origin，
 *   所以浏览器里带 Authorization 或 Content-Type: application/json 的 POST/PUT 全被拦。
 *   （不带自定义头的简单 GET 是通的，所以只登录/写操作挂，很容易误判成别的问题。）
 *
 *   安卓端是起本地 HTTP 服务 + /api 反代绕开的。iOS 上自己写 socket 服务风险太高，
 *   这里改成把 fetch 整个接管过来交给原生 URLSession 发 —— 不走浏览器网络栈，
 *   既没有同源限制，也完全不碰 CORS。（WKURLSchemeHandler 行不通：它拿不到 POST body。）
 *
 * 另外 QLNative.loadState() 是**同步**调用的，而 WKScriptMessageHandler 是异步的，
 * 所以本地存储不能走桥：原生在创建 WKUserScript 时把值直接嵌进 __QL_STATE_JSON__。
 */
(function () {
  if (window.__QL_IOS_BRIDGE__) return;
  window.__QL_IOS_BRIDGE__ = 1;

  /* 让页面里的 `window.__QL_NATIVE__` 分支生效（安卓壳里注入的是 'android'） */
  window.__QL_NATIVE__ = 'ios';

  var STATE = __QL_STATE_JSON__;

  window.QLNative = {
    loadState: function () { return STATE || ''; },
    saveState: function (v) {
      STATE = (v == null ? '' : String(v));
      try { window.webkit.messageHandlers.qlstate.postMessage(STATE); } catch (e) {}
    },
    setTarget: function (v) {
      try { window.webkit.messageHandlers.qltarget.postMessage(String(v == null ? '' : v)); } catch (e) {}
    },
    /* 「现在能不能返回上一页」。页面是单视图 SPA、**完全没用 history API**
       （底部 tab 切视图 + 弹层），所以系统的返回手势没有历史栈可用 —— 只能由页面
       自己算，再告诉原生。原生拿到后决定左边缘右滑手势的 isEnabled。
       传的是**裸布尔**（不是对象），见 QLBridge.swift 里的分派。 */
    setBack: function (on) {
      try { window.webkit.messageHandlers.qlback.postMessage(!!on); } catch (e) {}
    },
    /* 页面当前是深色还是浅色，原生据此切状态栏文字颜色。
       不通知的话：手机是深色、用户在设置里把页面强制成浅色时，
       状态栏还是白字，压在浅色页面上基本看不见。 */
    setTheme: function (v) {
      try {
        window.webkit.messageHandlers.qltheme.postMessage(v === 'dark' ? 'dark' : 'light');
      } catch (e) {}
    },
    saveFile: function (name, b64, id) {
      try {
        window.webkit.messageHandlers.qlsave.postMessage({
          name: String(name == null ? '' : name),
          b64: String(b64 == null ? '' : b64),
          id: String(id == null ? '' : id)
        });
      } catch (e) {
        if (window.__qlSaved) window.__qlSaved(id, false, '原生桥不可用');
      }
    }
  };

  /* ---------------- fetch 接管 ---------------- */

  var seq = 0;
  var pending = {};

  function b64ToBytes(s) {
    var bin = atob(s);
    var n = bin.length;
    var u = new Uint8Array(n);
    for (var i = 0; i < n; i++) u[i] = bin.charCodeAt(i);
    return u;
  }

  function fileToB64(f) {
    return new Promise(function (resolve, reject) {
      var fr = new FileReader();
      fr.onload = function () {
        var s = String(fr.result || '');
        var i = s.indexOf(',');
        resolve(i >= 0 ? s.slice(i + 1) : s);
      };
      fr.onerror = function () { reject(new Error('读取文件失败')); };
      fr.readAsDataURL(f);
    });
  }

  /* Headers 对象过不了 bridge（只能传 plist 兼容类型），先摊平成普通对象 */
  function normHeaders(h) {
    var out = {};
    if (!h) return out;
    try {
      if (typeof h.forEach === 'function') {
        h.forEach(function (v, k) { out[String(k).toLowerCase()] = String(v); });
        return out;
      }
      Object.keys(h).forEach(function (k) { out[String(k).toLowerCase()] = String(h[k]); });
    } catch (e) {}
    return out;
  }

  function serBody(body) {
    if (body == null) return Promise.resolve(null);
    if (typeof body === 'string') return Promise.resolve({ t: 'text', v: body });
    if (typeof URLSearchParams !== 'undefined' && body instanceof URLSearchParams) {
      return Promise.resolve({ t: 'text', v: body.toString() });
    }
    /* FormData：字段名 + 值，带文件的读成 base64（不能直接传 File 过桥） */
    if (typeof body === 'object' && typeof body.append === 'function') {
      var parts = [];
      var jobs = [];
      function each(fn) {
        if (typeof body.forEach === 'function') { body.forEach(fn); return; }
        if (typeof body.entries === 'function') {
          var it = body.entries();
          var e = it.next();
          while (!e.done) { fn(e.value[1], e.value[0]); e = it.next(); }
        }
      }
      each(function (v, k) {
        if (typeof File !== 'undefined' && v instanceof File) {
          jobs.push(fileToB64(v).then(function (b) {
            parts.push({ n: String(k), f: v.name || 'file', m: v.type || 'application/octet-stream', b: b });
          }));
        } else {
          parts.push({ n: String(k), v: String(v) });
        }
      });
      return Promise.all(jobs).then(function () { return { t: 'form', p: parts }; });
    }
    return Promise.resolve({ t: 'text', v: String(body) });
  }

  window.fetch = function (input, init) {
    var url = (typeof input === 'string') ? input : (input && input.url);
    init = init || {};
    if (!url) return Promise.reject(new TypeError('请求地址为空'));

    var id = ++seq;
    return new Promise(function (resolve, reject) {
      pending[id] = { resolve: resolve, reject: reject };
      serBody(init.body).then(function (b) {
        try {
          window.webkit.messageHandlers.qlnet.postMessage({
            id: id,
            url: String(url),
            method: String(init.method || 'GET').toUpperCase(),
            headers: normHeaders(init.headers),
            body: b
          });
        } catch (e) {
          delete pending[id];
          reject(new TypeError('原生桥不可用'));
        }
      }).catch(function (e) {
        delete pending[id];
        reject(e);
      });
    });
  };

  /* 原生回执。构造真正的 Response，好让页面里的 res.ok / res.text() / res.blob() 都能用。 */
  window.__qlNetDone = function (id, status, headers, b64) {
    var e = pending[id];
    if (!e) return;
    delete pending[id];
    var body = null;
    /* 204/205/304 带 body 会让 Response 构造抛错 */
    if (b64 && b64.length && status !== 204 && status !== 205 && status !== 304) {
      try { body = b64ToBytes(b64); } catch (err) { body = null; }
    }
    try {
      e.resolve(new Response(body, { status: status, statusText: '', headers: headers || {} }));
    } catch (err) {
      e.reject(new TypeError('HTTP ' + status));
    }
  };

  window.__qlNetFail = function (id, message) {
    var e = pending[id];
    if (!e) return;
    delete pending[id];
    e.reject(new TypeError(message || '网络错误'));
  };
})();
