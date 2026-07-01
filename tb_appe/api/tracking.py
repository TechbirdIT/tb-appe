import frappe


@frappe.whitelist()
def get_employee_tracking(employee, date):

    doc = frappe.get_doc(
        "Appe Employee Route Summary",
        {
            "employee": employee,
            "summary_date": date
        }
    )

    return {
        "employee": doc.employee,
        "date": doc.summary_date,
        "distance": doc.total_distance_km,
        "points": doc.total_points,
        "activities": doc.total_activities,
        "start_time": doc.start_time,
        "end_time": doc.end_time,
        "route_geojson": doc.route_geojson,
        # Renamed doctype exposes activity/timeline data as activity_geojson.
        "timeline_json": doc.get("activity_geojson"),
        "activity_geojson": doc.get("activity_geojson"),
    }