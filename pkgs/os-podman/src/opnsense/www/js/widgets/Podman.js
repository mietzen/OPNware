/*
 * Copyright (C) 2026 Nils Stein
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES,
 * INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
 * AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
 * AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY,
 * OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

export default class Podman extends BaseTableWidget {
    constructor(config) {
        super(config);
    }

    getGridOptions() {
        return {
            sizeToContent: 650
        };
    }

    getMarkup() {
        let $table = this.createTable('podmanContainersTable', {
            headerPosition: 'left'
        });
        return $(`<div id="podman-container"></div>`).append($table);
    }

    async onWidgetTick() {
        const podmanService = await this.ajaxCall('/api/podman/service/status');
        if (!podmanService || podmanService.status !== 'running') {
            this.displayError(this.translations.service_stopped || 'Podman service is not running', '/ui/podman/general');
            return;
        }

        const response = await this.ajaxCall('/api/podman/containers/list');
        const items = (response && Array.isArray(response.items)) ? response.items : [];

        // Filter only running containers
        const runningContainers = items.filter(c => {
            const st = (c.State || '').toLowerCase();
            const status = (c.Status || '').toLowerCase();
            return st === 'running' || st === 'up' || status.startsWith('up');
        });

        if (runningContainers.length === 0) {
            this.displayMessage(this.translations.no_running_containers || 'No running containers', '/ui/podman/dashboard');
            return;
        }

        if (!this.dataChanged('podman-running-containers', runningContainers)) {
            return;
        }

        $('#podmanContainersTable').empty();
        this.processContainers(runningContainers);
    }

    displayError(message, linkHref) {
        $('#podmanContainersTable').empty().append(
            `<div class="error-message" style="text-align: center; padding: 10px;"><a href="${linkHref || '/ui/podman/dashboard'}">${message}</a></div>`
        );
    }

    displayMessage(message, linkHref) {
        $('#podmanContainersTable').empty().append(
            `<div class="text-muted" style="text-align: center; padding: 12px;"><a href="${linkHref || '/ui/podman/dashboard'}">${message}</a></div>`
        );
    }

    escapeHtml(str) {
        if (!str) return '';
        return String(str)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#039;');
    }

    processContainers(containers) {
        $('[data-toggle="tooltip"]').tooltip('hide');

        containers.forEach(c => {
            const rawNames = c.Names || c.Name || '';
            const cname = (Array.isArray(rawNames) ? (rawNames[0] || '--') : String(rawNames)).replace(/^\//, '');
            const cid = c.Id || c.ID || '';
            const shortId = cid.length > 12 ? cid.substring(0, 12) : cid;
            const imageTag = c.Image || c.ImageName || '--';
            const status = c.Status || c.State || 'Running';

            let portList = [];
            if (Array.isArray(c.Ports)) {
                c.Ports.forEach(p => {
                    if (typeof p === 'object' && p !== null) {
                        const hostPort = p.hostPort || p.HostPort || p.host_port;
                        const containerPort = p.containerPort || p.ContainerPort || p.container_port;
                        if (hostPort && containerPort) {
                            portList.push(`${hostPort}:${containerPort}`);
                        } else if (containerPort) {
                            portList.push(`${containerPort}`);
                        }
                    } else if (typeof p === 'string') {
                        portList.push(p);
                    }
                });
            }

            const portsStr = portList.length > 0 ? portList.join(', ') : '';

            const header = `
                <div style="display: flex; justify-content: space-between; align-items: center; width: 100%;">
                    <div style="display: flex; align-items: center; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">
                        <i class="fa fa-cube text-success" style="font-size: 12px; margin-right: 6px; flex-shrink: 0;" data-toggle="tooltip" title="${this.escapeHtml(cid)}"></i>
                        <a href="/ui/podman/dashboard" style="font-weight: bold; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">
                            ${this.escapeHtml(cname)}
                        </a>
                    </div>
                    <span class="label label-success" style="font-size: 10px; margin-left: 8px; flex-shrink: 0;">${this.translations.running || 'RUNNING'}</span>
                </div>
            `;

            const row = `
                <div style="display: flex; justify-content: space-between; align-items: center; width: 100%; font-size: 12px;">
                    <div style="overflow: hidden; text-overflow: ellipsis; white-space: nowrap; max-width: 60%;">
                        <span class="text-muted"><i class="fa fa-clone"></i> </span><code>${this.escapeHtml(imageTag)}</code>
                    </div>
                    <div class="text-muted" style="font-size: 11px; text-align: right; flex-shrink: 0;">
                        ${portsStr ? `<span title="Ports: ${this.escapeHtml(portsStr)}"><i class="fa fa-exchange"></i> ${this.escapeHtml(portsStr)} | </span>` : ''}
                        <span>${this.escapeHtml(status)}</span>
                    </div>
                </div>
            `;

            super.updateTable('podmanContainersTable', [[header, row]], cid || cname);
        });

        $('[data-toggle="tooltip"]').tooltip({ container: 'body' });
    }
}
