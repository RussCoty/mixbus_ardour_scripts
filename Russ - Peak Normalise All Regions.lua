ardour { ["type"] = "EditorAction", name = "Normalise All Regions",
	license     = "MIT",
	author      = "Ardour Team? Modified by Russell Cottier",
	description = [[Normalise all regions On Timeline]]
}

function factory () return function ()
	-- get Editor GUI Selection
	-- http://manual.ardour.org/lua-scripting/class_reference/#ArdourUI:Selection
	local sl = ArdourUI.SelectionList () -- empty selection list

	local sel = Editor:get_selection ()

	-- prepare undo operation
	Session:begin_reversible_command ("Lua Normalize")
	local add_undo = false -- keep track if something has changed

-- for each selected track/bus..
	for route in sel.tracks:routelist ():iter () do
		-- consider only tracks
		local track = route:to_track ()
		if track:isnil() then
			goto continue
		end

		-- iterate over all regions of the given track
		for region in track:playlist():region_list():iter() do
		
				-- get RegionView (GUI object to be selected)
				local rv = Editor:regionview_from_region (region)
				-- add it to the list of Objects to be selected
				sl:push_back (rv);
		end
		::continue::
	end
	-- set/replace current selection in the editor
	Editor:set_selection (sl, ArdourUI.SelectionOp.Set);


	-- iterate over selected regions
	-- http://manual.ardour.org/lua-scripting/class_reference/#ArdourUI:RegionSelection
	for r in sel.regions:regionlist ():iter () do
		-- test if it's an audio region
		local ar = r:to_audioregion ();
		if ar:isnil () then 
			goto next
		end

		local peak = ar:maximum_amplitude (nil);
		local rms  = ar:rms (nil);

		if (peak > 0) then
			print ("Region:", r:name (), "peak:", 20 * math.log (peak) / math.log(10), "dBFS")
			print ("Region:", r:name (), "rms :", 20 * math.log (rms) / math.log(10), "dBFS")
		else
			print ("Region:", r:name (), " is silent")
		end

		-- normalize region
		if (peak > 0) then
			-- prepare for undo
			r:to_stateful ():clear_changes ()
			-- calculate gain.  
			local f_rms = rms / 10 ^ (.05 * -18) -- -18dBFS/RMS
			local f_peak = peak / 10 ^ (.05 * -1) -- -1dbFS/peak
			-- apply gain
			if (f_rms > f_peak) then
				print ("Region:", r:name (), "RMS  normalized by:", -20 * math.log (f_rms) / math.log(10), "dB")
				ar:set_scale_amplitude (1 / f_rms)
			else 
				print ("Region:", r:name (), "peak normalized by:", -20 * math.log (f_peak) / math.log(10), "dB")
				ar:set_scale_amplitude (1 / f_peak)
			end
			-- save changes (if any) to undo command
			if not Session:add_stateful_diff_command (r:to_statefuldestructible ()):empty () then
				add_undo = true
			end 
		end

		::next::
	end

	-- all done. now commit the combined undo operation
	if add_undo then
		-- the 'nil' command here means to use all collected diffs
		Session:commit_reversible_command (nil)
	else
		Session:abort_reversible_command ()
	end

end end
