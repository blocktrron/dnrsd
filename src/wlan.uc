'use strict';

export function ie_array_get_id(ie_array, ie_id) {
	for (let ie in ie_array) {
		if (int(ie.id) == ie_id) {
			return ie;
		}
	}

	return null;
};

export function ie_array_get_vsid(ie_array, oui, subtype) {
	for (let ie in ie_array) {
		if (int(ie.id) != 0xDD) {
			continue;
		}

		if (length(ie.data) < 4) {
			continue;
		}

		let ie_oui = substr(ie.data, 0, 6);
		let ie_subtype = hex(substr(ie.data, 6, 2));

		if (ie_oui != oui || ie_subtype != subtype) {
			continue;
		}

		return ie;
	}

	return null;
};

export function ie_array_get_ssid(ie_array) {
	let ssid_ie = ie_array_get_id(ie_array, 0x00);
	if (ssid_ie == null) {
		return null;
	}

	return hexdec(ssid_ie.data);
};

function ie_array_from_array_handle_ie(frame_str) {
	if (length(frame_str) == 0) {
		return [];
	}

	if (length(frame_str) < 4) {
		return null;
	}

	let ie_id = hex(substr(frame_str, 0, 2));
	let ie_len = hex(substr(frame_str, 2, 2));
	let ie_data = substr(frame_str, 4, ie_len * 2);
	let remaining_str = substr(frame_str, 4 + ie_len * 2);

	let ie = {
		id: ie_id,
		len: ie_len,
		data: ie_data,
	};

	let next_ie = ie_array_from_array_handle_ie(remaining_str);
	if (next_ie == null) {
		return null;
	}

	push(next_ie, ie);

	return next_ie;
}

export function ie_array_from_array(frame_body_str, fragment_id_str) {
	/* I did not find out from the spec in which order a beacon report
	 * is fragmented. We just assume what wpa_supplicant does is right,
	 * which assumes that the last fragment is the one containing the fixed elements.
	 */

	let frag_id = hex(fragment_id_str);
	let offset = 0;
	if (!(frag_id & 0x01)) {
		/* Skip fixed elements */
		offset += 12 * 2
	}
	
	let frame_body = substr(frame_body_str, offset);
	let frame_array = ie_array_from_array_handle_ie(frame_body);
	if (frame_array == null) {
		printf('Failed to parse beacon report frame body: %s\n', frame_body_str);
		return;
	}

	return frame_array;
};
