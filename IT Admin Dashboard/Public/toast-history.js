/*
    toast-history.js
    Bell icon in the top-right of the IT Admin Portal that keeps a timestamped list of every toast.

    - Every toast that pops up is saved in this browser (localStorage) with the time it appeared.
    - Entries older than 24 hours are purged automatically.
    - The red badge shows how many toasts arrived since you last opened the list.
    - "Clear" empties the list in this browser.

    Loaded by app.ps1 with: Import-PodeWebJavaScript -Url '/toast-history.js'
*/
(function () {
    'use strict';

    var STORE_KEY = 'portalToastHistory';
    var SEEN_KEY = 'portalToastHistorySeen';
    var MAX_AGE_MS = 24 * 60 * 60 * 1000;

    // ---------- storage ----------
    function load() {
        try {
            var items = JSON.parse(window.localStorage.getItem(STORE_KEY) || '[]');
            return Array.isArray(items) ? items : [];
        } catch (e) { return []; }
    }

    function save(items) {
        try { window.localStorage.setItem(STORE_KEY, JSON.stringify(items)); } catch (e) { /* storage full or blocked */ }
    }

    function purge() {
        var cutoff = Date.now() - MAX_AGE_MS;
        var items = load().filter(function (i) { return i && i.t >= cutoff; });
        save(items);
        return items;
    }

    function lastSeen() {
        try { return parseInt(window.localStorage.getItem(SEEN_KEY) || '0', 10) || 0; } catch (e) { return 0; }
    }

    function markSeen() {
        try { window.localStorage.setItem(SEEN_KEY, String(Date.now())); } catch (e) { /* ignore */ }
    }

    // ---------- styles ----------
    var css = [
        '.th-bell{position:relative;display:inline-flex;align-items:center;justify-content:center;width:38px;height:38px;',
        'margin-left:auto;margin-right:8px;border-radius:50%;cursor:pointer;color:#fff;font-size:1.4em;user-select:none}',
        '.th-bell:hover{background:rgba(255,255,255,.15)}',
        '.th-bell.th-floating{position:fixed;top:10px;right:16px;z-index:99998;background:#2c3e63}',
        '.th-badge{position:absolute;top:2px;right:2px;min-width:18px;height:18px;padding:0 5px;border-radius:9px;',
        'background:#dc3545;color:#fff;font-size:11px;line-height:18px;text-align:center;font-weight:bold}',
        '.th-panel{position:fixed;z-index:99999;width:380px;max-width:calc(100vw - 24px);background:#1e2a44;color:#fff;',
        'border:1px solid #3b5ba5;border-radius:6px;box-shadow:0 6px 18px rgba(0,0,0,.5);font-size:.9em}',
        '.th-head{display:flex;align-items:center;justify-content:space-between;padding:8px 12px;border-bottom:1px solid #3b5ba5;font-weight:bold}',
        '.th-head button{padding:2px 10px;border-radius:4px;border:1px solid #3b5ba5;background:#2c3e63;color:#fff;cursor:pointer;font-weight:normal}',
        '.th-list{max-height:420px;overflow:auto}',
        '.th-item{padding:8px 12px;border-bottom:1px solid rgba(59,91,165,.5)}',
        '.th-item:last-child{border-bottom:none}',
        '.th-time{font-size:.8em;opacity:.7}',
        '.th-title{font-weight:bold;margin:2px 0}',
        '.th-title.th-error{color:#ff8a8a}',
        '.th-msg{white-space:pre-wrap;word-break:break-word}',
        '.th-empty{padding:16px 12px;opacity:.7;text-align:center}'
    ].join('');

    var style = document.createElement('style');
    style.textContent = css;
    document.head.appendChild(style);

    // ---------- bell + badge ----------
    var bell = document.createElement('span');
    bell.className = 'th-bell';
    bell.title = 'Notification history (last 24 hours)';

    var icon = document.createElement('span');
    icon.className = 'mdi mdi-bell-outline';
    bell.appendChild(icon);

    var badge = document.createElement('span');
    badge.className = 'th-badge';
    badge.style.display = 'none';
    bell.appendChild(badge);

    function placeBell() {
        if (bell.isConnected) { return; }
        var nav = document.querySelector('nav.navbar, .navbar');
        if (nav) {
            bell.classList.remove('th-floating');
            nav.appendChild(bell);
        } else if (document.body) {
            bell.classList.add('th-floating');
            document.body.appendChild(bell);
        }
    }

    function updateBadge() {
        var seen = lastSeen();
        var unread = load().filter(function (i) { return i.t > seen; }).length;
        badge.textContent = unread > 99 ? '99+' : String(unread);
        badge.style.display = unread > 0 ? '' : 'none';
    }

    // ---------- panel ----------
    var panel = null;

    function closePanel() {
        if (panel) { panel.remove(); panel = null; }
    }

    function openPanel() {
        closePanel();
        var items = purge().slice().reverse(); // newest first

        panel = document.createElement('div');
        panel.className = 'th-panel';
        panel.addEventListener('click', function (e) { e.stopPropagation(); });

        var head = document.createElement('div');
        head.className = 'th-head';
        var heading = document.createElement('span');
        heading.textContent = 'Notifications (last 24 hours)';
        var clear = document.createElement('button');
        clear.type = 'button';
        clear.textContent = 'Clear';
        clear.addEventListener('click', function () { save([]); openPanel(); updateBadge(); });
        head.appendChild(heading);
        head.appendChild(clear);
        panel.appendChild(head);

        var list = document.createElement('div');
        list.className = 'th-list';

        if (items.length === 0) {
            var empty = document.createElement('div');
            empty.className = 'th-empty';
            empty.textContent = 'No notifications in the last 24 hours.';
            list.appendChild(empty);
        }

        items.forEach(function (i) {
            var row = document.createElement('div');
            row.className = 'th-item';

            var time = document.createElement('div');
            time.className = 'th-time';
            time.textContent = new Date(i.t).toLocaleString();

            var title = document.createElement('div');
            title.className = 'th-title' + (/fail|error/i.test(i.title || '') ? ' th-error' : '');
            title.textContent = i.title || 'Message';

            var msg = document.createElement('div');
            msg.className = 'th-msg';
            msg.textContent = i.msg || '';

            row.appendChild(time);
            row.appendChild(title);
            row.appendChild(msg);
            list.appendChild(row);
        });

        panel.appendChild(list);
        document.body.appendChild(panel);

        var rect = bell.getBoundingClientRect();
        var width = panel.offsetWidth || 380;
        var left = Math.min(rect.right - width, document.documentElement.clientWidth - width - 12);
        panel.style.left = Math.max(12, left) + 'px';
        panel.style.top = (rect.bottom + 6) + 'px';

        markSeen();
        updateBadge();
    }

    bell.addEventListener('click', function (e) {
        e.stopPropagation();
        if (panel) { closePanel(); } else { openPanel(); }
    });
    document.addEventListener('click', closePanel);
    document.addEventListener('keydown', function (e) { if (e.key === 'Escape') { closePanel(); } });

    // ---------- capture toasts ----------
    function textOf(root, selector) {
        var el = root.querySelector(selector);
        return el ? (el.textContent || '').trim() : '';
    }

    function capture(toast) {
        if (toast.getAttribute('data-th-logged')) { return; }
        toast.setAttribute('data-th-logged', '1');

        var title = textOf(toast, '.toast-header strong') || textOf(toast, '.toast-header') || 'Message';
        var msg = textOf(toast, '.toast-body');
        if (!msg) { return; }

        var items = purge();
        items.push({ t: Date.now(), title: title.replace(/\s*×\s*$/, ''), msg: msg, page: window.location.pathname });
        save(items);
        updateBadge();
        if (panel) { openPanel(); }
    }

    function scanNode(node) {
        if (!node || node.nodeType !== 1) { return; }
        if (node.classList.contains('toast')) { capture(node); }
        var toasts = node.querySelectorAll ? node.querySelectorAll('.toast') : [];
        for (var i = 0; i < toasts.length; i++) { capture(toasts[i]); }
    }

    new MutationObserver(function (mutations) {
        mutations.forEach(function (m) {
            for (var i = 0; i < m.addedNodes.length; i++) { scanNode(m.addedNodes[i]); }
        });
        placeBell();
    }).observe(document.documentElement, { childList: true, subtree: true });

    // ---------- start ----------
    function start() {
        placeBell();
        purge();
        updateBadge();
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', start);
    } else {
        start();
    }

    // Purge old entries every 10 minutes while the page is open
    setInterval(function () { purge(); updateBadge(); }, 10 * 60 * 1000);
})();
