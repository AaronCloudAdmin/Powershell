/*
    table-filters.js
    Excel-style sort and filter dropdowns on every table header in the IT Admin Portal.

    - A small arrow appears in each column header. Click it for:
        Sort A to Z / Sort Z to A, Clear Filter, a search box, Select All, and a checkbox per value.
    - Filters on several columns combine (like Excel).
    - Filters reset automatically when the table gets new data (a new search or report).
    - "Download filtered (CSV)" above each table exports only the rows you can see.
    - User tables (with a SamAccountName column): single-click a row selects that user (highlighted,
      and sent to the server for sidebar actions); double-click opens the user's details.

    Loaded by app.ps1 with: Import-PodeWebJavaScript -Url '/table-filters.js'
*/
(function () {
    'use strict';

    var BLANK = '(Blanks)';

    // ---------- page refresh clears results ----------
    // "Back to Search" loads the page with ?restore=1 so the server keeps the last search/report.
    // Remove that marker from the address bar right away, so a browser refresh afterwards starts clean.
    var SEL_KEY = 'portalSelectedUser';
    try {
        var url = new URL(window.location.href);
        var restoring = url.searchParams.get('restore') === '1';
        var opening = !!url.searchParams.get('value');
        var searchPage = /\/Active_Directory$/i.test(url.pathname);

        // Fresh load of the Active Directory page (refresh / sidebar): forget the highlighted selection, like the server does
        if (searchPage && !restoring && !opening) {
            try { window.sessionStorage.removeItem(SEL_KEY); } catch (e2) { /* ignore */ }
        }

        if (restoring) {
            url.searchParams.delete('restore');
            window.history.replaceState(window.history.state, '', url.pathname + url.search + url.hash);
        }
    } catch (e) { /* older browser: ignore */ }

    // ---------- styles ----------
    var css = [
        '.xf-btn{display:inline-block;margin-left:6px;padding:0 5px;border:1px solid rgba(255,255,255,.35);border-radius:3px;',
        'font-size:.75em;line-height:1.4em;cursor:pointer;user-select:none;opacity:.8}',
        '.xf-btn:hover{opacity:1;background:rgba(255,255,255,.15)}',
        '.xf-btn.xf-active{background:#f0ad4e;color:#000;border-color:#f0ad4e;opacity:1}',
        'tr.xf-hidden{display:none !important}',
        '[id^="ADSidebar"]{display:none !important}',
        '.xf-subitem > a{padding-left:2.4em !important;font-size:.95em;white-space:nowrap}',
        // Wider sidebar (fixed 280px on screens 768px and up) so every action fits on one line.
        // Main content and the top-left title box follow the same width. Hiding the sidebar still works.
        '@media (min-width:768px){',
        'nav#sidebarMenu{flex:0 0 280px !important;max-width:280px !important;width:280px !important}',
        '.navbar-brand.col-md-3{flex:0 0 280px !important;max-width:280px !important;width:280px !important}',
        'main[role="main"]:not(.fullscreen){flex:0 0 calc(100% - 280px) !important;max-width:calc(100% - 280px) !important;margin-left:280px !important}',
        '}',
        'tr.xf-selected > td{background:rgba(240,173,78,.35) !important}',
        'tr.xf-selected{outline:2px solid #f0ad4e;outline-offset:-2px}',
        '.xf-menu{position:absolute;z-index:99999;width:280px;background:#1e2a44;color:#fff;border:1px solid #3b5ba5;',
        'border-radius:6px;box-shadow:0 6px 18px rgba(0,0,0,.5);font-size:.9em;padding:6px 0}',
        '.xf-item{padding:6px 14px;cursor:pointer}',
        '.xf-item:hover{background:#2c3e63}',
        '.xf-item.xf-disabled{opacity:.4;cursor:default}',
        '.xf-item.xf-disabled:hover{background:none}',
        '.xf-sep{border-top:1px solid #3b5ba5;margin:4px 0}',
        '.xf-search{margin:6px 12px;width:calc(100% - 24px);padding:4px 8px;border-radius:4px;border:1px solid #3b5ba5;',
        'background:#111a2e;color:#fff}',
        '.xf-list{max-height:240px;overflow:auto;margin:0 12px;padding:4px 6px;border:1px solid #3b5ba5;border-radius:4px;background:#111a2e}',
        '.xf-list label{display:block;white-space:nowrap;margin:2px 0;cursor:pointer}',
        '.xf-list input{margin-right:6px}',
        '.xf-actions{display:flex;justify-content:flex-end;gap:8px;padding:8px 12px 4px}',
        '.xf-actions button{padding:3px 14px;border-radius:4px;border:1px solid #3b5ba5;background:#2c3e63;color:#fff;cursor:pointer}',
        '.xf-actions button.xf-apply{background:#0d6efd;border-color:#0d6efd}',
        '.xf-actions button:disabled{opacity:.4;cursor:default}',
        '.xf-export{display:inline-block;margin:6px 0;padding:3px 12px;border-radius:4px;border:1px solid #3b5ba5;',
        'background:#2c3e63;color:#fff;cursor:pointer;font-size:.85em}',
        '.xf-export:hover{background:#3b5ba5}'
    ].join('');

    var style = document.createElement('style');
    style.textContent = css;
    document.head.appendChild(style);

    // ---------- helpers ----------
    function cellText(row, col) {
        var cell = row.cells[col];
        var text = cell ? (cell.textContent || '').trim() : '';
        if (text === '' || text === 'undefined' || text === 'null') { return BLANK; }
        return text;
    }

    function bodyRows(table) {
        var rows = [];
        for (var b = 0; b < table.tBodies.length; b++) {
            var tb = table.tBodies[b];
            for (var r = 0; r < tb.rows.length; r++) { rows.push(tb.rows[r]); }
        }
        return rows;
    }

    function compare(a, b) {
        if (a === BLANK && b !== BLANK) { return 1; }
        if (b === BLANK && a !== BLANK) { return -1; }
        return a.localeCompare(b, undefined, { numeric: true, sensitivity: 'base' });
    }

    function rowPasses(table, row, skipCol) {
        var filters = table._xfFilters || {};
        for (var key in filters) {
            if (!Object.prototype.hasOwnProperty.call(filters, key)) { continue; }
            var col = parseInt(key, 10);
            if (col === skipCol) { continue; }
            if (!filters[key].has(cellText(row, col))) { return false; }
        }
        return true;
    }

    function applyFilters(table) {
        bodyRows(table).forEach(function (row) {
            row.classList.toggle('xf-hidden', !rowPasses(table, row, -1));
        });
        updateButtons(table);
    }

    function updateButtons(table) {
        var filters = table._xfFilters || {};
        var head = table.tHead;
        if (!head || !head.rows[0]) { return; }
        var cells = head.rows[0].cells;
        for (var c = 0; c < cells.length; c++) {
            var btn = cells[c].querySelector('.xf-btn');
            if (btn) { btn.classList.toggle('xf-active', Object.prototype.hasOwnProperty.call(filters, String(c))); }
        }
    }

    function sortTable(table, col, direction) {
        table.tBodies.length && Array.prototype.forEach.call(table.tBodies, function (tb) {
            var rows = Array.prototype.slice.call(tb.rows);
            rows.sort(function (a, b) {
                var result = compare(cellText(a, col), cellText(b, col));
                return direction === 'desc' ? -result : result;
            });
            rows.forEach(function (row) { tb.appendChild(row); });
        });
        // Re-ordering rows is not new data: drop those change notices so filters are kept.
        if (table._xfObserver) { table._xfObserver.takeRecords(); }
    }

    function headerLabel(th) {
        return th.getAttribute('data-xf-label') || (th.textContent || '').trim();
    }

    // ---------- dropdown menu ----------
    var menu = null;

    function closeMenu() {
        if (menu) { menu.remove(); menu = null; }
    }

    function openMenu(table, col, anchor) {
        closeMenu();

        var filters = table._xfFilters || (table._xfFilters = {});
        var current = filters[String(col)] || null;

        // Values offered = values in rows that pass the OTHER columns' filters (Excel behaviour)
        var seen = {};
        bodyRows(table).forEach(function (row) {
            if (rowPasses(table, row, col)) { seen[cellText(row, col)] = true; }
        });
        var values = Object.keys(seen).sort(compare);

        menu = document.createElement('div');
        menu.className = 'xf-menu';
        menu.addEventListener('click', function (e) { e.stopPropagation(); });

        function addItem(text, handler, disabled) {
            var item = document.createElement('div');
            item.className = 'xf-item' + (disabled ? ' xf-disabled' : '');
            item.textContent = text;
            if (!disabled) { item.addEventListener('click', handler); }
            menu.appendChild(item);
        }

        addItem('Sort A to Z', function () { sortTable(table, col, 'asc'); closeMenu(); });
        addItem('Sort Z to A', function () { sortTable(table, col, 'desc'); closeMenu(); });

        var sep = document.createElement('div');
        sep.className = 'xf-sep';
        menu.appendChild(sep);

        addItem('Clear Filter from "' + headerLabel(anchor.parentNode) + '"', function () {
            delete filters[String(col)];
            applyFilters(table);
            closeMenu();
        }, !current);

        var search = document.createElement('input');
        search.type = 'text';
        search.placeholder = 'Search';
        search.className = 'xf-search';
        menu.appendChild(search);

        var list = document.createElement('div');
        list.className = 'xf-list';
        menu.appendChild(list);

        var allLabel = document.createElement('label');
        var allBox = document.createElement('input');
        allBox.type = 'checkbox';
        allLabel.appendChild(allBox);
        allLabel.appendChild(document.createTextNode('(Select All)'));
        list.appendChild(allLabel);

        var boxes = values.map(function (value) {
            var label = document.createElement('label');
            var box = document.createElement('input');
            box.type = 'checkbox';
            box.value = value;
            box.checked = !current || current.has(value);
            label.appendChild(box);
            label.appendChild(document.createTextNode(value));
            list.appendChild(label);
            return { label: label, box: box };
        });

        var actions = document.createElement('div');
        actions.className = 'xf-actions';
        var cancel = document.createElement('button');
        cancel.type = 'button';
        cancel.textContent = 'Cancel';
        var apply = document.createElement('button');
        apply.type = 'button';
        apply.className = 'xf-apply';
        apply.textContent = 'Apply';
        actions.appendChild(cancel);
        actions.appendChild(apply);
        menu.appendChild(actions);

        function visibleBoxes() {
            return boxes.filter(function (b) { return b.label.style.display !== 'none'; });
        }

        function refreshState() {
            var vis = visibleBoxes();
            var checked = vis.filter(function (b) { return b.box.checked; }).length;
            allBox.checked = vis.length > 0 && checked === vis.length;
            allBox.indeterminate = checked > 0 && checked < vis.length;
            apply.disabled = boxes.every(function (b) { return !b.box.checked; });
        }

        allBox.addEventListener('change', function () {
            visibleBoxes().forEach(function (b) { b.box.checked = allBox.checked; });
            refreshState();
        });
        boxes.forEach(function (b) { b.box.addEventListener('change', refreshState); });

        search.addEventListener('input', function () {
            var term = search.value.toLowerCase();
            boxes.forEach(function (b) {
                b.label.style.display = b.box.value.toLowerCase().indexOf(term) >= 0 ? '' : 'none';
            });
            refreshState();
        });

        cancel.addEventListener('click', closeMenu);

        apply.addEventListener('click', function () {
            // When searching, Excel applies only the visible (matching) values
            var source = search.value ? visibleBoxes() : boxes;
            var chosen = source.filter(function (b) { return b.box.checked; }).map(function (b) { return b.box.value; });

            if (!search.value && chosen.length === boxes.length) {
                delete filters[String(col)];
            } else {
                filters[String(col)] = new Set(chosen);
            }
            applyFilters(table);
            closeMenu();
        });

        refreshState();

        document.body.appendChild(menu);
        var rect = anchor.getBoundingClientRect();
        var left = rect.left + window.scrollX;
        var maxLeft = window.scrollX + document.documentElement.clientWidth - menu.offsetWidth - 8;
        menu.style.left = Math.max(8, Math.min(left, maxLeft)) + 'px';
        menu.style.top = (rect.bottom + window.scrollY + 4) + 'px';
        search.focus();
    }

    document.addEventListener('click', closeMenu);
    document.addEventListener('keydown', function (e) { if (e.key === 'Escape') { closeMenu(); } });

    // ---------- CSV export of visible rows ----------
    function csvValue(text) {
        if (text === BLANK) { text = ''; }
        return '"' + String(text).replace(/"/g, '""') + '"';
    }

    function exportVisible(table) {
        var head = table.tHead;
        if (!head || !head.rows[0]) { return; }
        var headers = Array.prototype.map.call(head.rows[0].cells, function (th) { return csvValue(headerLabel(th)); });
        var lines = [headers.join(',')];

        bodyRows(table).forEach(function (row) {
            if (row.classList.contains('xf-hidden') || window.getComputedStyle(row).display === 'none') { return; }
            var values = [];
            for (var c = 0; c < head.rows[0].cells.length; c++) { values.push(csvValue(cellText(row, c))); }
            lines.push(values.join(','));
        });

        var blob = new Blob([lines.join('\r\n')], { type: 'text/csv;charset=utf-8;' });
        var link = document.createElement('a');
        link.href = URL.createObjectURL(blob);
        link.download = (table.id || 'table') + '.csv';
        document.body.appendChild(link);
        link.click();
        setTimeout(function () { URL.revokeObjectURL(link.href); link.remove(); }, 0);
    }

    // ---------- row selection: single-click selects, double-click opens ----------
    // Only for tables that have a SamAccountName column (user results).
    function columnIndex(table, label) {
        var head = table && table.tHead;
        if (!head || !head.rows[0]) { return -1; }
        var cells = head.rows[0].cells;
        for (var c = 0; c < cells.length; c++) {
            if (headerLabel(cells[c]) === label) { return c; }
        }
        return -1;
    }

    function storedSelection() {
        try { return JSON.parse(window.sessionStorage.getItem(SEL_KEY) || 'null'); } catch (e) { return null; }
    }

    function highlightSelection() {
        var sel = storedSelection();
        var tables = document.querySelectorAll('table');
        for (var i = 0; i < tables.length; i++) {
            var samCol = columnIndex(tables[i], 'SamAccountName');
            if (samCol < 0) { continue; }
            bodyRows(tables[i]).forEach(function (row) {
                row.classList.toggle('xf-selected', !!sel && cellText(row, samCol) === sel.sam);
            });
        }
    }

    function userRowFromEvent(e) {
        var target = e.target;
        if (!target || !target.closest) { return null; }
        if (target.closest('a, button, input, select, textarea, thead')) { return null; }
        var row = target.closest('tbody tr');
        if (!row) { return null; }
        var table = row.closest('table');
        var samCol = columnIndex(table, 'SamAccountName');
        if (samCol < 0) { return null; }
        return { row: row, table: table, sam: cellText(row, samCol), name: cellText(row, columnIndex(table, 'DisplayName')) };
    }

    // Capture phase, so Pode.Web's own row-click (which opens the user) does not fire
    window.addEventListener('click', function (e) {
        var hit = userRowFromEvent(e);
        if (!hit || !hit.sam || hit.sam === BLANK) { return; }
        e.stopPropagation();
        e.preventDefault();

        var name = hit.name === BLANK ? '' : hit.name;
        try { window.sessionStorage.setItem(SEL_KEY, JSON.stringify({ sam: hit.sam, name: name })); } catch (e2) { /* ignore */ }
        highlightSelection();

        // Tell the server, so sidebar actions (Unlock, ...) know who is selected
        try {
            fetch('/api/ad/select', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ sam: hit.sam, name: name })
            });
        } catch (e3) { /* ignore */ }
    }, true);

    window.addEventListener('dblclick', function (e) {
        var hit = userRowFromEvent(e);
        if (!hit || !hit.sam || hit.sam === BLANK) { return; }
        e.stopPropagation();
        e.preventDefault();
        window.location.href = window.location.pathname + '?value=' + encodeURIComponent(hit.sam);
    }, true);

    // ---------- sidebar actions under "Active Directory" ----------
    // Each item clicks a hidden button on the Active Directory page (id ADSidebar...), so the
    // action runs on the server like any other Pode.Web button. Add more actions to this list.
    var AD_ACTIONS = [
        { label: 'Unlock Account', icon: 'lock-open-variant', trigger: 'ADSidebarUnlock', colour: '#17a2b8' },
        { label: 'Reset Password', icon: 'lock-reset', trigger: 'ADSidebarReset', colour: '#17a2b8' },
        { label: 'ENABLE Account', icon: 'account-check', trigger: 'ADSidebarEnable', colour: '#17a2b8' },
        { label: 'COPY User', icon: 'account-multiple-plus', trigger: 'ADSidebarCopy', colour: '#17a2b8' },
        { label: 'Edit Name / Email', icon: 'account-edit', trigger: 'ADSidebarEditName', colour: '#28a745' },
        { label: 'Edit Groups', icon: 'account-group', trigger: 'ADSidebarGroups', colour: '#28a745' },
        { label: 'Title Change', icon: 'briefcase-edit', trigger: 'ADSidebarTitle', colour: '#28a745' },
        { label: 'Manager Change', icon: 'account-tie', trigger: 'ADSidebarManager', colour: '#28a745' },
        { label: 'Update Phone Number', icon: 'phone', trigger: 'ADSidebarPhone', colour: '#28a745' },
        { label: 'Move User', icon: 'folder-move', trigger: 'ADSidebarMove', colour: '#28a745' },
        { label: 'Update Notes', icon: 'note-edit', trigger: 'ADSidebarNotes', colour: '#28a745' },
        { label: 'LOA Start', icon: 'calendar-start', trigger: 'ADSidebarLOAStart', colour: '#ffc107' },
        { label: 'LOA Return', icon: 'calendar-end', trigger: 'ADSidebarLOAEnd', colour: '#ffc107' },
        { label: 'DISABLE User', icon: 'account-off', trigger: 'ADSidebarDisable', colour: '#dc3545' },
        { label: 'DISABLE and AIRLOCK', icon: 'shield-lock', trigger: 'ADSidebarAirlock', colour: '#dc3545' }
    ];

    function findNavLink(text) {
        var links = document.querySelectorAll('nav a, #sidebar a, .sidebar a, aside a');
        for (var i = 0; i < links.length; i++) {
            if ((links[i].textContent || '').trim() === text) { return links[i]; }
        }
        return null;
    }

    function runAdAction(action) {
        var el = document.getElementById(action.trigger);
        if (el && el.tagName !== 'BUTTON') { el = el.querySelector('button') || el; }

        if (!el) {
            // Not on the Active Directory page: go there (keeping results); click the item again there
            var adLink = findNavLink('Active Directory');
            if (adLink) { window.location.href = adLink.getAttribute('href').split('?')[0] + '?restore=1'; }
            return;
        }
        el.click();
    }

    function addSidebarActions() {
        var adLink = findNavLink('Active Directory');
        if (!adLink) { return; }
        var adItem = adLink.closest('li') || adLink;
        if (adItem.getAttribute('data-xf-actions')) { return; }
        adItem.setAttribute('data-xf-actions', '1');

        var insertAfter = adItem;
        AD_ACTIONS.forEach(function (action) {
            var item = adItem.cloneNode(true);
            item.removeAttribute('data-xf-actions');
            item.removeAttribute('id');
            item.classList.add('xf-subitem');

            var link = item.tagName === 'A' ? item : item.querySelector('a');
            link.classList.remove('active');
            link.removeAttribute('id');
            link.setAttribute('href', '#');

            // Replace the label (keep the icon element, swap its icon)
            var iconEl = link.querySelector('.mdi');
            while (link.firstChild) { link.removeChild(link.firstChild); }
            if (iconEl) {
                iconEl.className = iconEl.className.replace(/mdi-[\w-]+/g, '').trim() + ' mdi-' + action.icon;
                link.appendChild(iconEl);
                link.appendChild(document.createTextNode(' '));
            }
            link.appendChild(document.createTextNode(action.label));

            // Colour strip on the left
            if (action.colour) { link.style.borderLeft = '4px solid ' + action.colour; }

            link.addEventListener('click', function (e) {
                e.preventDefault();
                e.stopPropagation();
                runAdAction(action);
            }, true);

            insertAfter.parentNode.insertBefore(item, insertAfter.nextSibling);
            insertAfter = item;
        });
    }

    // ---------- attach to tables ----------
    function enhance(table) {
        var head = table.tHead;
        if (!head || !head.rows[0]) { return; }

        var cells = head.rows[0].cells;
        for (var c = 0; c < cells.length; c++) {
            var th = cells[c];
            if (th.querySelector('.xf-btn')) { continue; }
            th.setAttribute('data-xf-label', (th.textContent || '').trim());

            var btn = document.createElement('span');
            btn.className = 'xf-btn';
            btn.title = 'Sort and filter';
            btn.textContent = '▾';
            (function (col, button) {
                button.addEventListener('click', function (e) {
                    e.stopPropagation();
                    e.preventDefault();
                    openMenu(table, col, button);
                });
            })(c, btn);
            th.appendChild(btn);
        }

        // Export button above the table (once)
        if (!table._xfExport) {
            var exp = document.createElement('button');
            exp.type = 'button';
            exp.className = 'xf-export';
            exp.textContent = 'Download filtered (CSV)';
            exp.addEventListener('click', function () { exportVisible(table); });
            table.parentNode.insertBefore(exp, table);
            table._xfExport = exp;
        }

        // New rows from the server = new data: reset this table's filters
        // (Watches the whole table, so it still works if the table body is replaced.)
        if (!table._xfObserver) {
            table._xfObserver = new MutationObserver(function () {
                table._xfFilters = {};
                updateButtons(table);
            });
            table._xfObserver.observe(table, { childList: true, subtree: true });
        }

        updateButtons(table);
    }

    function scan() {
        var tables = document.querySelectorAll('table');
        for (var i = 0; i < tables.length; i++) {
            if (tables[i].tHead && tables[i].tHead.rows.length) { enhance(tables[i]); }
        }
        highlightSelection();
        addSidebarActions();
    }

    var pending = null;
    new MutationObserver(function () {
        if (pending) { return; }
        pending = setTimeout(function () { pending = null; scan(); }, 150);
    }).observe(document.documentElement, { childList: true, subtree: true });

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', scan);
    } else {
        scan();
    }
})();