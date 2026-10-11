'use strict';
'require view';
'require home-net.common as management';
return view.extend({
 load: function() { return management.load(); },
 render: function(data) { return management.render('Overview', data); },
 handleSaveApply: null, handleSave: null, handleReset: null
});
