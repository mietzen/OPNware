/*
 * Copyright (C) 2026 Nils Stein
 * All rights reserved.
 */

export default class Logwatch extends BaseTableWidget {
    constructor(config) {
        super(config);
    }

    getGridOptions() {
        return { sizeToContent: 650 };
    }

    getMarkup() {
        const $table = this.createTable('logwatchWidgetTable', {
            headerPosition: 'left'
        });
        return $('<div id="logwatch-widget-container"></div>').append($table);
    }

    esc(str) {
        if (!str) {
            return '';
        }
        return String(str)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    async onWidgetTick() {
        const svc = await this.ajaxCall('/api/logwatch/service/status');
        const st = await this.ajaxCall('/api/logwatch/logs/stats');
        if (!st || st.status !== 'ok') {
            return;
        }

        const sig = JSON.stringify([svc && svc.status, st]);
        if (!this.dataChanged('logwatch-widget-state', sig)) {
            return;
        }

        $('#logwatchWidgetTable').empty();
        const running = svc && svc.status === 'running';
        const statusBadge = running
            ? `<span class="label label-success">${this.translations.running || 'Running'}</span>`
            : `<span class="label label-default">${this.translations.stopped || 'Stopped'}</span>`;

        const summaryHeader = `
            <div style="display:flex; justify-content:space-between; align-items:center; width:100%;">
                <a href="/ui/logwatch/logs" style="font-weight:bold;"><i class="fa fa-list-alt"></i> Logwatch</a>
                ${statusBadge}
            </div>
        `;
        const summaryRow = `
            <div style="display:flex; justify-content:space-between; align-items:center; flex-wrap:wrap; gap:6px; width:100%; font-size:12px;">
                <span style="display:inline-flex; flex-wrap:wrap; align-items:center; gap:4px;">
                    <a href="/ui/logwatch/logs?severity=err&preset=1h" class="label label-danger" title="1h Errors">${st.errors_1h || 0} err (1h)</a>
                    <a href="/ui/logwatch/logs?severity=warning&preset=1h" class="label label-warning" title="1h Warnings">${st.warnings_1h || 0} warn (1h)</a>
                    <a href="/ui/logwatch/logs?severity=err&preset=24h" class="text-muted" style="white-space:nowrap;">24h: ${st.errors_24h || 0}e / ${st.warnings_24h || 0}w</a>
                </span>
                <span class="text-muted" style="white-space:nowrap;">${st.total_rows || 0} rows (${st.db_size_mb || 0} MB)</span>
            </div>
        `;
        super.updateTable('logwatchWidgetTable', [[summaryHeader, summaryRow]], 'summary');

        const alerts = Array.isArray(st.recent_alerts) ? st.recent_alerts : [];
        alerts.forEach((a) => {
            const when = a.last_alerted_at ? new Date(a.last_alerted_at * 1000).toLocaleString() : '--';
            const hdr = `<a href="/ui/logwatch/rules"><i class="fa fa-bell text-warning"></i> ${this.esc(a.rule_name)}</a>`;
            const val = `<span class="text-muted" style="font-size:11px;">${a.last_count || 0} hits &middot; ${this.esc(when)}</span>`;
            super.updateTable('logwatchWidgetTable', [[hdr, val]], 'alert-' + a.rule_name);
        });
    }
}
