---
layout: post
title: "brain explained"
date: 2026-03-04
---

So I will try to explain the "other brain" that I've developed. It's mainly old code that I have tried to expand. Up until now I have been so focused on building a user friendly performance system that I kind of forgot to work with this code. 

Basically what it does is two things:
- Listen to what I do and store data. Then classify what kind of musical phrase I am doing.
- Let the brain make choices on how to adjust the system. 

I think it is best to start with the routine that I call, because from there we can dive in to the rest. 

```
~fb.otherbrain = { |self, i, button|
    var v = ~fbs[i];
    var silenceCounter = 0, silenceGrace = 40, isActive = false;
    var isPlaying, data;

	/*
	The "Manager" (Main Routine). This is what you call to start the "other brain". ~fb.otherbrain(index number, \play or \stop) -> very simple.
	It manages the silence between phrases. It waits for you to stop playing (silenceGrace), then triggers the classification and choice sequence.
	 It prevents the brain from making decisions while you are still in the middle of a gesture.

	*/

    // IMPORTANT: Ensure these exist so brainChoice doesn't crash
    if (v[\phraseCounter].isNil) { v[\phraseCounter] = 0 };
    if (v[\lastPending].isNil) { v[\lastPending] = \none };

    self.brainInit(i);

    if (button == \play) {
        v[\autoBrainRoutine] = Routine({
            "--- BRAIN START ---".postln;
            loop {
                isPlaying = self.brainListen(i);

                if (isPlaying) {
                    if (isActive == false) {
                        " > Listening...".postln;
                        v[\analysis][\startTime] = Main.elapsedTime; // Measures real time
                        isActive = true;
                    };
                    silenceCounter = 0;
                } {
                    if (isActive) {
                        silenceCounter = silenceCounter + 1;
                        if (silenceCounter >= silenceGrace) {
                            " > Processing...".postln;

                            // 1. Classify the phrase
                            data = self.brainClassify(i); // all data is provided from this routine and it goes into brainChoice. 

                            // 2. Make Choice (Wrapped in try to prevent Routine death)
                            try {
                                self.brainChoice(i, *data);
                            } { |error|
                                "!!! ERROR IN CHOICE: %".format(error).postln;
                            };

                            // 3. MANDATORY RESET: This must happen for the loop to continue
                            isActive = false;
                            silenceCounter = 0;
							// Call init WITHOUT hardReset so the routine keeps running!
							self.brainInit(i, false);

							" > Ready for next phrase...".postln;
                            " > Listening Loop Reset. Ready.".postln;
							"0.5s cooldown".postln;
							0.5.wait; // just to avoid phrases being called to tight. 
                        };
                    };
                };
                0.05.wait;
            }
        }).play;
    } { v[\autoBrainRoutine].stop; "--- BRAIN STOPPED ---".postln; };
};
```

This is basically just a routine that listen to amplitude and see if I'm playing. It is nothing advanced really. I use Main.elapsedTime to measure seconds in real time. I know there is a lot of ways to do this but I find this to be the best way. 

It checks "isPlaying" every 0.05s. It is ture if I play above threshold. isActive is telling us that we currently are inside a musical phrase. silenceCounter adds up every 0.05s until it reaches 2. If I then play something above thresh at tick 39 it will reset to 0 and the phrase is still playing. In a musical language this means: A phrase can have a maximum of 1.99999 seconds of silence. If longer, the system says that I have finished a phrase. 

The brain acts like an "Interrupter." It will process every tiny pause. Great for fast, glitchy dialogue. Higher (e.g., 100): The brain becomes a "Patient Listener." It waits 5 seconds for you to finish.

It would be possible to have a dynamic silenceGrace. Lets say I play rhytmically, then perhaps it would feel very unmusical to have these 2 second pauses after each phrase. 

So when the phrase has ended we go to fb.brainClassify. 

```
~fb.brainClassify = { |self, i|
    var v = ~fbs[i], a = v[\analysis];
    var activeTime = a[\activeLoops] * 0.05;
    var avgNoteDur = if(a[\noteCount] > 0) { activeTime / a[\noteCount] } { 0 };
    var pitchRange = if(a[\pitchList].size > 1) { (12 * (a[\pitchList].maxItem / a[\pitchList].minItem).log2) } { 0 };
    var avgFlat = if(a[\flatList].size > 0) { a[\flatList].mean } { 0 };
    var avgCent = if(a[\centList].size > 0) { a[\centList].mean } { 0 };
    var noiseStyle = if(activeTime < 1.0) { \breath } { \noise }; // Pre-calculate
    var finalStyle;

	/*
	 function looks at the gathered Lists and decides what "Style" you just played.
	Saves the result to v[\analysis][\currentPhrase].
 It outputs an Array of these values and passes them directly to brainChoice.
	*/

    "--- BRAIN [%] ANALYSIS REPORT ---".format(i).postln;
    "    > Dur: %s | Notes: % | Avg Note: %s".format(activeTime.round(0.1), a[\noteCount], avgNoteDur.round(0.01)).postln;
    "    > Pitch Range: % semitones".format(pitchRange.round(0.1)).postln;
    "    > Spectral: Flatness % | Centroid %".format(avgFlat.round(0.001), avgCent.round(1)).postln;
    "---------------------------------".postln;

    finalStyle = case
        { (a[\noteCount] >= 3) && (avgNoteDur < 0.5) } {
            "    [Decision] Logic: High density + short notes -> RHYTHMIC".postln;
            \rhythmic
        }
        { (avgFlat > 0.08) || (avgCent > 1200) } {
            "    [Decision] Logic: High noise/brightness -> %".format(noiseStyle.asString.toUpper).postln;
            noiseStyle
        }
        { pitchRange > 18.0 } {
            "    [Decision] Logic: Huge pitch leap (> 1.5 octaves) -> GESTURE".postln;
            \gesture
        }
        { (pitchRange >= 7.0 && (activeTime > 1.2)) || (a[\noteCount] >= 3 && (pitchRange >= 3.0)) } {
            "    [Decision] Logic: Intentional melodic movement -> MELODIC".postln;
            \melodic
        }
        { activeTime > 1.2 } {
            "    [Decision] Logic: Sustained sound with low movement -> LONG".postln;
            \long
        }
        { true } { // Default case
            "    [Decision] Logic: Too short/random -> FRAGMENT".postln;
            \fragment
        };

    v[\analysis][\currentPhrase] = finalStyle;
    [finalStyle, avgNoteDur, pitchRange, avgFlat, a[\noteCount]];
};
```

This measures a lot of stuff going on when playing. 

activeTime -> the actual time in seconds that I played above threshold.  A rhytmical phrase usually have quite a low activeTime on a phrase. While long notes have long activeTime
avgNoteDur -> Measures time from attack to lower than threshold on each note. 
pitchRange -> A pitchRange of 0 means you stayed on one note. 7.0 is a Perfect Fifth. 12.0 is an Octave. This tells the brain if you are playing "Melodically" or "Statically."
avgFlat -> This allows the brain to distinguish between a "Clean Note" (low flatness) and "Air/Noise/Distortion" (high flatness). Also good for making a separation between melodic and rhytmical. Flatness usually is high at a note attack. 
avgCent -> I added this so that it could hear if I was playing multiphonics or not. I really dont like using this because it is so dependent on knowing what instrument is used to set range. 

When it has calculated it's values it goes through a list ranging from rhytmic to long notes. 
It then checks: { (a[\noteCount] >= 3) && (avgNoteDur < 0.5) } { \rhythmic } -> if not move on. Here I have experimented with some different setups. I did include flat for a while but then a lot of noisy phrases became rhytmic. 

For melodic phrases I use || so that it allows both short notes in a melody and long notes. 

```
{ (pitchRange >= 7.0 && (activeTime > 1.2)) || (a[\noteCount] >= 3 && (pitchRange >= 3.0)) } { \melodic }
````

and just to show you how the "ears" look: 

```
~fb.brainListen = { |self, i|
    var v = ~fbs[i];
    var a = v[\analysis];
    var threshold = if (~soundchecked == false) {0.005} {~fbs[0][\softAmp]};
    var curAmp = v[\data][\ampBus].getSynchronous;
    var curTrig = v[\data][\trigBus].getSynchronous;
    var curPitch = v[\data][\pitchBus].getSynchronous;
    var ratio;

	/*
	The "Ears." It runs every 50ms (inside the otherbrain loop).

Values Generated: Real-time Amplitude, Pitch, Spectral Centroid, Flatness, and Trigger (onsets).

	If the amplitude is above threshold, it adds these values to the v[\analysis] Lists. It also increments activeLoops (to measure duration) and noteCount.
	*/

    if (curAmp > threshold) {
        a[\activeLoops] = a[\activeLoops] + 1;
        a[\flatList].add(~bus[i].ctl.flat.getSynchronous);
        a[\centList].add(~bus[i].ctl.cent.getSynchronous);

        // --- RESTORED PITCH LOGIC ---
        if (curPitch > 40) {
            if (a[\pitchList].size == 0) {
                a[\pitchList].add(curPitch);
                a[\lastValidPitch] = curPitch;
            } {
                ratio = curPitch / (a[\lastValidPitch] ? curPitch);
                if (ratio > 0.35 && (ratio < 3.0)) {
                    a[\pitchList].add(curPitch);
                    a[\lastValidPitch] = curPitch;
                };
            };
        };

        if (curTrig >= 1.0) { a[\noteCount] = a[\noteCount] + 1 };
        if (a[\activeLoops] % 10 == 0) { ".".post; };
        true;
    } { false };
};
```

So it just adds to a list that provides the fb.brainClassify with data to do some math on. 


Next thing in the fb.otherbrain that happens is to pass the data to fb.brainChoice. This is also a function that includes several parts. 

```
~fb.brainChoice = { |self, idx, style, dur, range, flat, count, avgNoteDur|
    var v = ~fbs[idx], dna, finalChain, possibleFx, weights, extraFx, currentCount, dynamicLerp;

    style = style.asSymbol;

    if (style == v[\lastPending] && (style != \fragment)) {
        v[\phraseCounter] = (v[\phraseCounter] + 1).min(10);
    } {
        v[\phraseCounter] = 1;
        v[\lastPending] = style;
        v[\hasTriggeredThisStyle] = false;
    };

    currentCount = v[\phraseCounter];
    dna = self.brainGetDNA(style);

    case
        { currentCount >= 6 } {
            "!!! [Brain] STAGNATION DETECTED !!!".postln;
            v[\phraseCounter] = 0;

            switch (style)
                { \noise } {
                    "    > Extreme Stagnation: Injecting percPressure Stress-Test.".postln;
                    self.activate(idx, \percPressure);
                    self.setParam(idx, \chaos, 0.95);
                }
                { \long } {
                    [\organ, \bells, \gritty, \percPressure].do({ |m| self.deactivate(idx, m) });
                    self.activate(idx, \perc);
                    self.activate(idx, \drums);
                }
                { \rhythmic } {
                    self.deactivate(idx, \percPressure);
                    [\drums, \perc, \glitch].do({ |m| self.deactivate(idx, m) });
                    ~fx.(idx, [\blur, \time, \verb]);
                }
                { \melodic } {
                    self.deactivate(idx, \percPressure);
                    self.activate(idx, \glitch);
                };
        }

        { currentCount == 3 && (v[\hasTriggeredThisStyle] != true) } {
            v[\hasTriggeredThisStyle] = true;
            possibleFx = [\blur, \time, \ring, \pitch, \locdelay, \binshift, \echo];
            weights = [0.1, 0.15, 0.2, 0.05, 0.13, 0.17, 0.16].normalizeSum;
            extraFx = possibleFx.wchoose(weights);

            finalChain = switch (style)
                { \long }     { [\blur, \time] }
                { \rhythmic } { [\echo, \ring] }
                { \melodic }  { [\pitch, \locdelay] }
                { \breath }   { [\blur, \binshift] }
                { \noise }    { [\ring, \binshift, \locdelay] }
                { \gesture }  { [\pitch, \echo] }
                { [\dry] };

            if (finalChain.includes(extraFx).not) { finalChain = finalChain ++ [extraFx] };
            self.brainConductor(idx, style, dna, finalChain);
        }

        { true } {
            dynamicLerp = (0.2 + (currentCount * 0.05)).min(0.5);
            "    [Choice] % (Phrase %). Nudging...".format(style, currentCount).postln;
            self.brainNudge(idx, dna, dynamicLerp);
        };
};
```

So brainChoice gets a lot of data that are ordered in a specific way. 
I just added this state = state.asSymbol to be sure that it accepts both strings and symbols. I had strings for some time and then I forgot to change something.. Messy. 

I stop tiny failed phrases to become a part of a choice by using: 
(style == v[\lastPending] && (style != \fragment))

So then I use a phraseCounter. This measures how many of the phrases has been the same. If it is 3 phrases in a row that are melodic -> the brain says "we are in a melodic state". If it is 6 phrases in a row that are melodic the brain says "BORING!" and makes some countermove. I find this especially effective when I play long notes, because it is really easy to get stuck. 

So it uses a case to check the phraseCounter. 
For the boredom state it checks if the current state is, e.g, \long. If the system is bored it then deactivates typical \long-ambient-style modules. And then adds a \perc module. 

If it's just 3 in a row it changes things up. Adding and deactivating some modules and changing the fx-chain. It then checks the fb.brainConductor:

```
~fb.brainConductor = { |self, i, style, dna, fxChain|
    var v = ~fbs[i];
    var primaryMod = dna[\primary];

    "*** CONDUCTOR: % (Primary: %) ***".format(style.asString.toUpper, primaryMod).postln;

    // 1. Swap FX
    try { ~fx.(i, fxChain) } { |err| "FX Swap failed".postln };

    // 2. Force the Primary Module
    if (primaryMod.notNil) { self.activate(i, primaryMod) };

    // 3. Set parameters
    [\dens, \space, \chaos, \focus].do { |param|
        var val = dna[param] ?? 0.5;
        self.setParam(i, param, val);
        v[\modParams][param] = val;
    };

    // --- TEACHER ADDITION: Confirmation Message ---
    "    [Conductor] Snap complete. FX: % | Primary: %".format(fxChain, primaryMod).postln;
};

```

It first swaps fx. Then checks for primaryMod which is set in fb.brainGetDNA. 
The third step is to set parameters. It gets that from fb.brainGetDNA(which is called in brainChoice and passes the dna values to the brainConductor). 

So it starts to get a little bit sweaty to describe this. 

In brainChoice I end with this: 
```
    { true } {
            dynamicLerp = (0.2 + (currentCount * 0.05)).min(0.5);
            "    [Choice] % (Phrase %). Nudging...".format(style, currentCount).postln;
            self.brainNudge(idx, dna, dynamicLerp);
        };
```

The first linear interpolation(lerp) is used to adjust how reactive the brain is. So if I play melodic 1 time it moves the params closer to melodic values, but only with 0.2 + (1 * 0.05), so 25 %. If I would like the brain more reactive I would raise the multiplier, perhaps to 0.1, but that makes it quite reactive. 

Then I call fb.brainNudge which is a big pile of settings: 

```
~fb.brainNudge = { |self, i, targetDNA, lerp = 0.35|
    var v = ~fbs[i];
    var mod = v[\modParams];
    var pLerp = lerp * 0.5;
    var threshold = if (~soundchecked == false) {0.005} {~fbs[0][\softAmp]};
    var curAmp = v[\data][\ampBus].getSynchronous;
    var pref, choice;

	/*
	The "Evolution." It gradually moves the synth parameters toward the DNA targets.

	Interpolated floats (using lerp). This is dynamically changed in brainChoice.

	It also has a 30% chance to randomly pick a module from the DNA list and activate it.



	*/

    if (mod.isNil) { ^self };

    // --- SMART MODULE MANAGEMENT ---
    if (0.3.coin) {
        pref = targetDNA[\modules] ?? [];
        choice = pref.choose;

        // CALM PROTECTION: Force-kill percPressure if playing softly
        if (curAmp < (threshold * 1.2)) {
            if (v[\modules][\percPressure][\active] == true) {
                "    [Brain] Too calm for Pressure. Deactivating...".postln;
                self.deactivate(i, \percPressure);
            };
        };

        // INTENSITY GATE: Only allow percPressure if Chaos/Dens are high
        if (choice == \percPressure) {
            if ((mod[\chaos] ?? 0) > 0.7 && ((mod[\dens] ?? 0) > 0.6)) {
                self.activate(i, \percPressure);
                "    [Nudge] Intensity High: Activating percPressure.".postln;
            } {
                // Not wild enough? Pick a safer alternative from the list
                self.activate(i, pref.reject({|m| m == \percPressure}).choose);
            };
        } {
            if (choice.notNil) { self.activate(i, choice) };
        };

        self.brainCleanup(i, targetDNA);
    };

    // --- PARAMETER INTERPOLATION ---
    mod[\dens]  = ((mod[\dens]  ?? 0.5) + ((targetDNA[\dens]  - (mod[\dens]  ?? 0.5)) * lerp)).clip(0,1);
    mod[\space] = ((mod[\space] ?? 0.5) + ((targetDNA[\space] - (mod[\space] ?? 0.5)) * lerp)).clip(0,1);
    mod[\chaos] = ((mod[\chaos] ?? 0.5) + ((targetDNA[\chaos] - (mod[\chaos] ?? 0.5)) * lerp)).clip(0,1);
    mod[\focus] = ((mod[\focus] ?? 0.5) + ((targetDNA[\focus] - (mod[\focus] ?? 0.5)) * lerp)).clip(0,1);

    if (~prc.notNil) {
        try {
            var nChaos = ((mod[\chaos] ?? 0.5) + ((targetDNA[\pChaos] - (mod[\chaos] ?? 0.5)) * pLerp)).clip(0,1);
            var nDens  = ((mod[\dens]  ?? 0.5) + ((targetDNA[\pDens]  - (mod[\dens]  ?? 0.5)) * pLerp)).clip(0,1);
            var nSpace = ((mod[\space] ?? 0.5) + ((targetDNA[\pSpace] - (mod[\space] ?? 0.5)) * pLerp)).clip(0,1);
            var nIdent = ((mod[\focus] ?? 0.5) + ((targetDNA[\pIdent] - (mod[\focus] ?? 0.5)) * pLerp)).clip(0.6,1);

            ~prc.percept(i, [\chaos, nChaos]);
            ~prc.percept(i, [\density, nDens]);
            ~prc.percept(i, [\space, nSpace]);
            ~prc.percept(i, [\identity, nIdent]);
        } { |err| "--- Perceptual nudge error: % ---".format(err).postln; };
    };

    "    [Nudge] Params: ".post;
    mod.keysValuesDo { |k, val|
        self.setParam(i, k, val);
        "%: % | ".format(k, val.round(0.01)).post;
    };
    "".postln;
};
```

This makes small adjustments to the system. Adds modules, deactivates them. Change params for modules and also for fx. 

So perhaps this is not the brain you thought it would be in a AI-driven world. Fortunatley, AI is not too focused on understanding how I want to play and how I find electronics to be problematic in a live improvisation context. 


