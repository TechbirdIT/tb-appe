// Copyright (c) 2025, kamesh3928@gmail.com and contributors
// For license information, please see license.txt

frappe.ui.form.on('Mobile App Module', {
    setup(frm) {

        frm.set_query("refrence_doctype", "items", function(doc, cdt, cdn) {
            let row = locals[cdt][cdn];

            if (row.type === "Single Doctype") {
                return {
                    filters: {
                        issingle: 1
                    }
                };
            }

            
        });

       

    }
});

frappe.ui.form.on('Mobile App Module Items', {
    type(frm, cdt, cdn) {
        let row = locals[cdt][cdn];
        row.refrence_doctype = "";
        if (row.type === "Report") {
                frappe.model.set_value(cdt, cdn, "refrence_doctype", "Appe Report");
                frm.fields_dict.items.grid.grid_rows_by_docname[cdn].toggle_editable("refrence_doctype", false);
            }
            else if (row.type === "Dashboard") {
                frappe.model.set_value(cdt, cdn, "refrence_doctype", "Dashboard");
                frm.fields_dict.items.grid.grid_rows_by_docname[cdn].toggle_editable("refrence_doctype", false);
            }
            else if (row.type === "Workspace") {
                frappe.model.set_value(cdt, cdn, "refrence_doctype", "Workspace");
                frm.fields_dict.items.grid.grid_rows_by_docname[cdn].toggle_editable("refrence_doctype", false);
            }

            else if (row.type === "Screen") {
                frappe.model.set_value(cdt, cdn, "refrence_doctype", "Appe Screen");
                frm.fields_dict.items.grid.grid_rows_by_docname[cdn].toggle_editable("refrence_doctype", false);
            }
            else{
                frappe.model.set_value(cdt, cdn, "refrence_doctype", "");
                frm.fields_dict.items.grid.grid_rows_by_docname[cdn].toggle_editable("refrence_doctype", true);
            }

        frm.refresh_field("items");
    },

   
    refrence_docname(frm, cdt, cdn) {
        let row = locals[cdt][cdn];
        if (row.type === "Screen" && row.refrence_docname) {
            frappe.db.get_value(
                "Appe Screen",
                row.refrence_docname,
                "route",
                function(r) {
                    console.log(r)
                    if (r && r.route) {
                        frappe.model.set_value(cdt, cdn, "screen_name", r.route);
                    }
                }
            );
        }
                frm.refresh_field("items");

    }




});