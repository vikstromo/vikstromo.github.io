(
~soundcheck = {
    Routine({
        var noiseReadings = [], sustainReadings = [], attackReadings = [];
        var noiseFloor, sustainFloor, attackFloor, percentileIndex;
		var soundchecksynth;
        var bus = ~bus[0].ctl.scAmp; // Using your existing analysis bus


		soundchecksynth = Synth(\soundCheck, [\in, ~bus[0].raw, \ampBus, bus], ~fbs[0][\firstGroup], \addToTail);

        "--- STEP 1: SILENCE (4s) ---".postln;
        "Don't move or blow...".postln;
        80.do {
			noiseReadings = noiseReadings.add(bus.getSynchronous.postln); 0.05.wait;

		};

		noiseReadings = noiseReadings.sort;
		percentileIndex = (noiseReadings.size * 0.95).floor;
        noiseFloor = noiseReadings[percentileIndex];
        "Result -> Noise Floor: %".format(noiseFloor.round(0.0001)).postln;

        2.wait;
        "--- STEP 2: SOFT SUSTAIN (4s) ---".postln;
        "Play your softest stable long note...".postln;
        80.do { sustainReadings = sustainReadings.add(bus.getSynchronous.postln); 0.05.wait; };
        // We take the median of your playing to find the stable center
        sustainFloor = sustainReadings.median;
        "Result -> Soft Sustain: %".format(sustainFloor.round(0.0001)).postln;

		if (noiseFloor >= (sustainFloor * 0.8)) {
    "WARNING: High noise detected. Adjusting gate for safety.".postln;
    noiseFloor = sustainFloor * 0.5; // Force the gate to be half the volume of a note

			("noiseFloor set to: "++noiseFloor).postln;
};

        2.wait;
        "--- STEP 3: ATTACK HITS ---".postln;
        "Play 5 short staccato notes at comfortable volume...".postln;
        80.do {
            var val = bus.getSynchronous.postln;
            if(val > (sustainFloor * 2)) { attackReadings = attackReadings.add(val) };
            0.05.wait;
        };
        attackFloor = if(attackReadings.size > 0) { attackReadings.median } { sustainFloor * 2 };
        "Result -> Attack Median: %".format(attackFloor.round(0.0001)).postln;

        // --- CALCULATE SYSTEM VALUES ---
        // 1. Listen Threshold: Halfway between noise and softest note
        ~sysNoiseLimit = (noiseFloor + sustainFloor) / 2;

        // 2. Trigger Threshold: Just below your attack hit
        ~sysTrigLimit = attackFloor * 0.7;

        "--- CALIBRATION COMPLETE ---".postln;
        "Updating System...".postln;

        // Apply to running synths
        ~fbs[0][\listen][\synth].set(\noiseFloor, noiseFloor * 1.02);
        ~fbs[0][\data][\synth].set(\ampFloor, attackFloor * 0.65);

        // Save to modParams for future modules
		~fbs[0][\ampFloor] = (noiseFloor + sustainFloor) / 2;
		~fbs[0][\softAmp] = sustainFloor * 0.9;
        ~fbs[0][\atkThresh] = attackFloor * 0.7;

		soundchecksynth.free;
		~soundchecked = true;

    }).play;
};
)