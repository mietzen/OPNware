{#
 # Copyright (C) 2026 Nils Mietzen
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

<div class="content-box tab-content">
    <div id="general" class="tab-pane fade in active">
        {{ partial("layout_partials/base_form", ['fields': generalForm, 'id': 'frm_general-settings']) }}
    </div>
</div>

<div class="col-md-12">
    <hr/>
    <button class="btn btn-primary" id="saveAct" type="button"><b>{{ lang._('Save & Apply') }}</b> <i id="saveAct_progress" class=""></i></button>
</div>

<script>
$(document).ready(function() {
    var data_get_map = {'frm_general-settings': '/api/docker/general/get'};
    mapDataToFormUI(data_get_map).done(function() {
        formatTokenizersUI();
        $('.selectpicker').selectpicker('refresh');
    });

    // Query dynamic host hardware resources
    ajaxGet('/api/docker/general/host_resources', {}, function(data, status) {
        if (status === 'success' && data) {
            var maxMem = Math.max(512, memMb - 1024);

            var cpuInput = $('#docker\\.general\\.cpus');
            var memInput = $('#docker\\.general\\.memory');

            cpuInput.attr('max', cpus);
            memInput.attr('max', maxMem);

            if ($('#slider_cpus').length === 0) {
                cpuInput.after('<input type="range" id="slider_cpus" min="1" max="' + cpus + '" value="' + (cpuInput.val() || 2) + '" style="margin-top:5px;">');
                $('#slider_cpus').on('input change', function() {
                    cpuInput.val($(this).val());
                });
                cpuInput.on('input change', function() {
                    $('#slider_cpus').val($(this).val());
                });
            }

            if ($('#slider_mem').length === 0) {
                memInput.after('<input type="range" id="slider_mem" min="512" max="' + maxMem + '" step="256" value="' + (memInput.val() || 2048) + '" style="margin-top:5px;">');
                $('#slider_mem').on('input change', function() {
                    memInput.val($(this).val());
                });
                memInput.on('input change', function() {
                    $('#slider_mem').val($(this).val());
                });
            }

            var cpuHelp = "{{ lang._('Host available CPU cores: ') }}" + cpus + ". " + "{{ lang._('Allocated to microVM (1 - ') }}" + cpus + ").";
            var memHelp = "{{ lang._('Host physical RAM: ') }}" + memMb + " MB. " + "{{ lang._('Allocated to microVM (512 - ') }}" + maxMem + " MB).";
            var diskHelp = "{{ lang._('Storage pool free space: ') }}" + freeGb + " GB. " + "{{ lang._('Allocated sparse data disk for /var/lib/docker.') }}";

            cpuInput.closest('tr').find('small').text(cpuHelp);
            memInput.closest('tr').find('small').text(memHelp);
            $('#docker\\.general\\.disk_size').closest('tr').find('small').text(diskHelp);
        }
    });

    $('#saveAct').click(function() {
        saveFormToEndpoint('/api/docker/general/set', 'frm_general-settings', function() {
            ajaxCall('/api/docker/service/reconfigure', {}, function() {
                BootstrapDialog.show({
                    type: BootstrapDialog.TYPE_SUCCESS,
                    title: "{{ lang._('Docker Settings') }}",
                    message: "{{ lang._('Configuration saved and Docker service reconfigured.') }}",
                    buttons: [{
                        label: "{{ lang._('Close') }}",
                        action: function(dialogRef) {
                            dialogRef.close();
                        }
                    }]
                });
            });
        }, true);
    });
});
</script>
