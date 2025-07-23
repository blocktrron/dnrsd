#!/usr/bin/env ucode

'use strict';

import * as libubus from 'ubus';
import * as uloop from 'uloop';
import * as fs from 'fs';
import * as dnrsd_wlan from 'dnrsd.wlan';

let update_interval = 5 * 1000; // 5 seconds

uloop.init();

let uptime_start = null;
let uptime_now = null;

let hostapd_instances = {};
let ubus = libubus.connect();
let update_timer;
let update_iteration = 0;
let reported_neighbors = {};

function update_uptime() {
	let uptime_file = fs.open('/proc/uptime', 'r');
	if (uptime_file == null) {
		printf('Failed to open /proc/uptime\n');
		return;
	}

	let content = uptime_file.read('line');
	let uptime = int(split(content, '.')[0]);

	if (uptime_start == null) {
		uptime_start = uptime;
	}
	uptime_now = uptime;

	uptime_file.close();
}

function vap_set_neighbor_report_list(instance) {
	let neighbor_report_list_sorted = [];

	/* ToDo: more sophisticated sorting */
	for (let bssid, neighbor in reported_neighbors) {
		if (neighbor.ssid != instance.ssid) {
			continue;
		}

		if (neighbor.neighbor_report == null) {
			continue;
		}

		push(neighbor_report_list_sorted, [ bssid, neighbor.ssid, neighbor.neighbor_report]);
	}

	return neighbor_report_list_sorted;
}

function hostapd_ubus_subscriber_remove_cb() {
	/* Handled by object removal */
}

function hostapd_ubus_subscriber_notify_cb_beacon_report(obj) {
	if (!('optional-subelements' in obj.data))
		return;

	let report = {
		client_mac: obj.data.address,
		bssid: obj.data.bssid,
		opclass: obj.data['op-class'],
		channel: obj.data.channel,
		rssi: (obj.data.rcpi / 2) - 110,
		rcpi: obj.data.rcpi,
		rsni: obj.data.rsni
	};

	// Get Beacon Report frame body and fragment id
	let frame_body;
	let fragment_id;
	for (let subelement in obj.data['optional-subelements']['elements']) {
		if (int(subelement['id']) == 0x01) {
			frame_body = subelement['data'];
		} else if (int(subelement['id']) == 0x02) {
			fragment_id = subelement['data'];
		}
	}

	if (!frame_body || !fragment_id) {
		return;
	}

	let ie_array = dnrsd_wlan.ie_array_from_array(frame_body, fragment_id);
	if (!ie_array) {
		return;
	}

	if (!(report.bssid in reported_neighbors)) {
		reported_neighbors[report.bssid] = {
			bssid: report.bssid,
			channel: report.channel,
			opclass: report.opclass,
			reports_total: 0,
			neighbor_report: null,
			ssid: null,
			reports_rssi: [
				{ rssi_min: -59, rssi_max: -50, count: 0 },
				{ rssi_min: -69, rssi_max: -60, count: 0 },
				{ rssi_min: -79, rssi_max: -70, count: 0 },
				{ rssi_min: -89, rssi_max: -80, count: 0 },
				{ rssi_min: -99, rssi_max: -90, count: 0 },
				{ rssi_min: -109, rssi_max: -100, count: 0 },
				{ rssi_min: -119, rssi_max: -110, count: 0 },
				{ rssi_min: -129, rssi_max: -120, count: 0 },
			],
		};
	}

	let ssid = dnrsd_wlan.ie_array_get_ssid(ie_array);
	if (ssid != null) {
		reported_neighbors[report.bssid].ssid = ssid;
	}

	let nr = dnrsd_wlan.ie_array_get_vsid(ie_array, '2005b7', 0x4c);
	if (nr != null) {
		reported_neighbors[report.bssid].neighbor_report = substr(nr.data, 8);
	}

	if (!(hex(fragment_id) & 0x01)) {
		// This is the last fragment, we can process the report
		reported_neighbors[report.bssid].reports_total++;

		for (let rssi_range in reported_neighbors[report.bssid].reports_rssi) {
			if (report.rssi >= rssi_range.rssi_min && report.rssi < rssi_range.rssi_max) {
				rssi_range.count++;
				break;
			}
		}
	}
}

function hostapd_ubus_subscriber_notify_cb(obj) {
	// This function is called when a hostapd instance sends a notification
	// printf('hostapd ubus subscriber notify: %s %s %s\n', obj.type, obj.data, obj.info);
	if (obj.type != 'beacon-report')
		return;

	hostapd_ubus_subscriber_notify_cb_beacon_report(obj);
}

function hostapd_update(path, ifname) {
	let status = ubus.call(path, 'get_status');
	let clients = ubus.call(path, 'get_clients');
	let neighbor_report_element = ubus.call(path, 'rrm_nr_get_own');

	if (!(ifname in hostapd_instances)) {
		hostapd_instances[ifname] = {
			ifname: ifname,
			path: path,
			subscriber: ubus.subscriber(hostapd_ubus_subscriber_notify_cb, hostapd_ubus_subscriber_remove_cb),
			clients: {},
		};

		hostapd_instances[ifname].subscriber.subscribe(path);
	}

	/* Update VIF information */
	hostapd_instances[ifname].neighbor_report = neighbor_report_element.value[2];
	hostapd_instances[ifname].bssid = neighbor_report_element.value[0];
	hostapd_instances[ifname].ssid = neighbor_report_element.value[1];

	/* Update clients */
	for (let client_mac, client in clients.clients) {
		hostapd_instances[ifname].clients[client_mac] = {
			mac: client_mac,
			beacon_reports: {
				passive: !!(client.rrm[0] & 16),
				active: !!(client.rrm[0] & 32),
				table: !!(client.rrm[0] & 64)
			},
			update_iteration: update_iteration,
			statistics: {
				num_requests: 0,
				num_reports: 0,
			}
		};
	}

	/* Delete stale clients */
	for (let client_mac in hostapd_instances[ifname].clients) {
		if (hostapd_instances[ifname].clients[client_mac].update_iteration < update_iteration) {
			delete hostapd_instances[ifname].clients[client_mac];
		}
	}
}


function hostapd_add(path, obj) {
	let ifname = obj[1];

	printf('Adding new Interface path=%s ifname=%s\n', path, ifname);

	/* Enable neighbor reports from AP and beacon reports from STA */
	ubus.call(path, 'bss_mgmt_enable', { 'neighbor_report': true, 'beacon_report': true });

	/* Update information from hostapd */
	hostapd_update(path, ifname);
	
	/* Reset list of neighbor reports */
	ubus.call(path, 'rrm_nr_set', { list: [] });
}

function hostapd_remove(path, obj) {
	printf('Removing interface %s\n', path);
	let ifname = obj[1];

	/* Remove the subscriber */
	if (ifname in hostapd_instances) {
		hostapd_instances[ifname].subscriber.unsubscribe(path);
		hostapd_instances[ifname].subscriber.remove();
		hostapd_instances[ifname].subscriber = null;
	}

	delete hostapd_instances[ifname];
}

function ubus_listener_event(event, payload) {
	let id = payload.id;
	let path = payload.path;
	let object = split(path, '.');
	if (object[0] == 'hostapd' && object[1]) {
		if (event == 'ubus.object.add')
			hostapd_add(path, object);
		else
			hostapd_remove(path, object);
	}
}

function update_timer_action_should_run(action_interval) {
	return (update_iteration % int((10 * 1000) / update_interval) == 0);
}

function update_timer_run() {
	update_uptime();
	/* Update all hostapd instances */
	for (let ifname, instance in hostapd_instances) {
		hostapd_update(instance.path, ifname);
	}

	for (let ifname, instance in hostapd_instances) {
		if (update_timer_action_should_run(60)) {
			/* Set IE for own AP */
			ubus.call(instance.path, 'add_vendor_element', {
				oui: '2005b7',
				subtype: 0x4c,
				data: instance.neighbor_report
			});
		}

		/* Query devices for neighbor reports */
		for (let client_mac, client in instance.clients) {
			if (!client.beacon_reports.table) {
				continue;
			}

			if (!update_timer_action_should_run(10) && client.statistics.num_requests > 1) {
				continue;
			}

			ubus.call(instance.path, 'rrm_beacon_req', {
				addr: client_mac,
				mode: 2,
				op_class: 0,
				channel: 0,
				duration: 0,
				ssid: instance.ssid,
			});
		}

		/* Update neighbor report list */
		let neighbor_report_list_sorted = vap_set_neighbor_report_list(instance);
		if (length(neighbor_report_list_sorted) > 0) {
			let req_obj = {
				list: neighbor_report_list_sorted
			};
			ubus.call(instance.path, 'rrm_nr_set', req_obj);
		}
	}
	update_timer.set(update_interval);
	update_iteration++;
}

ubus.listener('ubus.object.add', ubus_listener_event);
ubus.listener('ubus.object.remove', ubus_listener_event);

update_uptime();

/* First update needs to be done manually */
let list = ubus.list();
for (let k, path in list) {
	let object = split(path, '.');
	if (object[0] != 'hostapd' || !object[1]) {
		continue;
	}
	hostapd_add(path, object);
}

/* Own ubus methods */
let ubus_methods = {
	'status': {
		call: function(request) {
			return {
				'status': 'ok',
				'instances': hostapd_instances
			};
		},
		args : {}
	},
	'reported_neighbors': {
		call: function(request) {
			return reported_neighbors;
		},
		args: {}
	},
};
ubus.publish('dnrsd', ubus_methods);

/* Schedule update timer */
update_timer = uloop.timer(update_interval, update_timer_run);

/* Run the main loop */
uloop.run();