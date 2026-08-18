{#
 # Copyright (C) 2026 Nils Stein
 # All rights reserved.
 #
 # Redistribution and use in source and binary forms, with or without
 # modification, are permitted provided that the following conditions are met:
 #
 # 1. Redistributions of source code must retain the above copyright notice,
 #    this list of conditions and the following disclaimer.
 #
 # 2. Redistributions in binary form must reproduce the above copyright
 #    notice, this list of conditions and the following disclaimer in the
 #    documentation and/or other materials provided with the distribution.
 #
 # THIS SOFTWARE IS PROVIDED ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES,
 # INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
 # AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
 # AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY,
 # OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 # SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 # INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 # CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 # ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 # POSSIBILITY OF SUCH DAMAGE.
 #}

<script>
    $(document).ready(function () {
        var data_get_map = {'frm_general-settings': '/api/podman/general/get'};
        mapDataToFormUI(data_get_map).done(function (data) {
            formatTokenizersUI();
            $('.selectpicker').selectpicker('refresh');
            updateServiceControlUI('podman');
        });

        $('#btn_save').click(function () {
            saveFormToEndpoint('/api/podman/general/set', 'frm_general-settings', function () {
                ajaxCall('/api/podman/service/reconfigure', {}, function (data, status) {
                    updateServiceControlUI('podman');
                });
            });
        });
    });
</script>

<ul class="nav nav-tabs" data-tabs="tabs" id="maintabs" style="margin-bottom: 0;">
    <li class="active"><a data-toggle="tab" href="#general">{{ lang._('General Settings') }}</a></li>
</ul>

<div class="content-box tab-content" style="padding-top: 0;">
    <div id="general" class="tab-pane fade in active">
        {{ partial("layout_partials/base_form", ['fields': generalForm, 'id': 'frm_general-settings']) }}
        <div class="col-md-12">
            <hr/>
            <button class="btn btn-primary" id="btn_save" type="button">
                <b>{{ lang._('Apply') }}</b> <i id="btn_save_progress"></i>
            </button>
            <br/><br/>
        </div>
    </div>
</div>
