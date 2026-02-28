/* fx_chain_2601052320.scd */

/*
Search for ~bus and change this to appropriate buses. It should be one bus that is going in to the chain and one that is going out!

*/

~fxChain = Array.newClear(32);

(
~dbg = { |tag, msg|
	if (~debug == true ) {
    ("[FXDBG][" ++ tag ++ "] " ++ msg).postln;
	} {nil}
};

		~fxDict = (
	delay: \delay, // Use this system for adding new synthdefs. They should use ReplaceOut!! So  type: synthdefname: \synthdefname when adding your own. Maybe you have to delete these if you dont have them.
	pitch: \pitch,
	time: \time,
	verb: \verb,
	formant: \formant,
	binshift: \binshift,
	grainDel: \grainDel,
	dry: \dry,
	bufgrain: \bufgrain,
	feed: \feed,
	blur: \blur,
	ring: \ring,
	echo: \echo,
	locdelay: \locdelay,
	);


// --- Create a new FX chain
~newFXChain = {
    ~dbg.("newFXChain", "creating new chain");
    (
        group: Group.before(~spatialGroup),
        synths: Array.new,
        buses: Array.new,
		outBus: nil,
		//spatialSynth: nil;
    )
};

// --- Ensure enough buses for the FX chain
~ensureFXBuses = { |chain|

    var needed = (chain[\synths].size - 1).max(0);

    // Free all existing buses
    chain[\buses].do(_.free);

    // Create exactly the number we need
    chain[\buses] = Array.fill(needed, {
        Bus.audio(s, 1)
    });

    ~dbg.("ensureFXBuses", "rebuilt buses, count: " ++ chain[\buses].size);
};


// --- Get or create an FX synth
~getOrCreateFX = { |chain, defName, index, inBus = nil, outBus = nil|
    var s;
    ~dbg.("getOrCreateFX", "request: " ++ defName);
    s = chain[\synths].detect { |x| x.defName == defName };
    if (s.isNil) {
        ~dbg.("getOrCreateFX", "creating synth: " ++ defName);
       s = Synth(defName, [\in, -1, \out, -1], chain[\group], \addToTail);
        chain[\synths].add(s);



    } {
        ~dbg.("getOrCreateFX", "reusing synth: " ++ defName);
    };

	if (defName == \bufgrain) {
    s.set(\buf, ~grainBuf[index]);
		~dbg.("getOrCreateFX", "setting grainbuf to index: " ++ index)
};
    s;
};

// --- Order FX synths in a chain
~orderFX = { |chain, orderedSynths|
    ~dbg.("orderFX", "ordering: " ++ orderedSynths.collect(_.defName).join(" → "));
    orderedSynths.do { |s| s.moveToTail(chain[\group]); };
    chain[\synths] = orderedSynths;
};


// --- Wire FX chain
~wireFXChain = { |index, chain|

    var synths = chain[\synths];
    var buses  = chain[\buses];
    var lastIndex;

    if (synths.isEmpty) { ^nil };

    lastIndex = synths.size - 1;

    synths.do { |s, i|

        var inBus, outBus;

        if (i == 0) {
            inBus = ~bus[index].fxIn;
        } {
            inBus = buses[i-1];
        };

        if (i == lastIndex) {
            outBus = ~bus[index].fxOut;
        } {
            outBus = buses[i];
        };

        if (inBus.isNil or: { outBus.isNil }) {
            ("Routing error: nil bus at index " ++ i).warn;
        };

        s.set(\in, inBus, \out, outBus);

        ("FX " ++ i ++ " [" ++ s.defName ++ "] IN: "
            ++ inBus ++ " OUT: " ++ outBus).postln;
    };
};



~freeFX = { |index|
    var chain = ~fxChain[index];
    if (chain.notNil) {
        chain[\synths].do { |fx| fx.set(\gate, 0); };
        chain[\buses].do(_.free);
        //~sendBus[index].free;

		chain[\group].freeAll;
		chain[\group].free;
    };
    ~fxChain[index] = nil;
};



~updateFXChain = { |index, newFXOrder, outBus|
    var chain, oldSynths, newSynths, toKeep, toRemove, toAdd, finalSynths, synth, lastFX;

    chain = ~fxChain[index] ?? { ~newFXChain.() };
    ~fxChain[index] = chain;

    oldSynths = chain[\synths];

    toKeep   = oldSynths.select { |s| newFXOrder.includes(s.defName) };
    toRemove = oldSynths.reject { |s| newFXOrder.includes(s.defName) };
    toAdd    = newFXOrder.reject { |key| toKeep.any { |s| s.defName == ~fxDict[key] } };

    // --- remove old FX not in new order
    toRemove.do { |s| s.set(\gate, 0, \fbEnable, 0); };

    // --- create new FX
    newSynths = toAdd.collect { |key|
        synth = ~getOrCreateFX.(chain, ~fxDict[key], index);
        synth.set(\fbEnable, 1);
        synth;
    };

    toKeep.do { |s| s.set(\fbEnable, 1); };

    finalSynths = newFXOrder.collect { |key|
        (toKeep ++ newSynths).detect { |s| s.defName == ~fxDict[key] }
    };

    ~orderFX.(chain, finalSynths);
    ~ensureFXBuses.(chain);

    // --- Wire FX chain (first synth -> last FX -> sendBus)
    ~wireFXChain.(index, chain, ~bus[index].fxIn, ~bus[index].fxOut);

 /*   // --- Make sure last FX sends to sendBus, spatial reads from sendBus
    if(chain[\synths].notEmpty) {
        lastFX = chain[\synths].last;
        lastFX.set(\out, ~bus[index].fxOut);
    };*/


    ~prc.applyPerceptToChain(index);
    ~dbg.("updateFXChain", "update complete for chain " ++ index);

};





// --- This is the only command you will use, and ~fxFree.
~fx = { |index, fxOrder, outBus|
    ~updateFXChain.(index, fxOrder, outBus);
};

~fxSet = { |index, fxKey, args|
    var chain, synth;

    chain = ~fxChain[index];
    if (chain.isNil) {
        ("fx" ++ index ++ " no chain").warn;
        ^nil;
    };

    // --- Normal FX
    synth = chain[\synths].detect { |s|
        s.defName == ~fxDict[fxKey]
    };

    if (synth.isNil) {
        ("fx" ++ index ++ " no synth: " ++ fxKey).warn;
        ^nil;
    };

    synth.set(*args);
    synth;
};


)
