Engine_Endless : CroneEngine {
	var server, deckBuses, deckMixers, voices, sampleBuffers, openHats;
	var n303Voices, n303SlidePending;
	var n808Tone=0.5, n808Decay=0.5, n808Drive=0.25, n808Variation=0.15;
	var n808Levels;
	var n303Waveform=0, n303Cutoff=0.45, n303Resonance=0.65, n303EnvMod=0.55;
	var n303Decay=0.45, n303Drive=0.3, n303SlideTime=0.35;

	*new { arg context, doneCallback;
		^super.new(context, doneCallback);
	}

	alloc {
		server = context.server;
		voices = List.new;
		sampleBuffers = Array.fill(16, { nil });
		deckBuses = Array.fill(2, { Bus.audio(server, 2) });
		openHats = Array.fill(2, { nil });
		n808Levels = Array.fill(6, { 1.0 });
		n303SlidePending = Array.fill(2, { false });

		SynthDef(\endlessDeckMixer, { arg inBus=0, out=0, level=1;
			var signal = In.ar(inBus, 2);
			Out.ar(out, signal * Lag.kr(level, 0.03));
		}).add;

		SynthDef(\endless808, {
			arg out=0, voice=1, amp=0.8, voiceLevel=1, toneControl=0.5,
				decayControl=0.5, driveControl=0.25, variation=0.15;
			var env, pitchEnv, noise, metallic, signal, voiceSignals;
			var baseDecay, decay, toneScale, randomPitch, driven;
			baseDecay = Select.kr(voice, #[0.48, 0.24, 0.20, 0.32, 0.075, 0.55]);
			decay = baseDecay * decayControl.linexp(0, 1, 0.45, 1.8);
			toneScale = toneControl.linexp(0, 1, 0.65, 1.55);
			randomPitch = Rand(-1.0, 1.0) * variation * 0.045;
			env = EnvGen.kr(Env.perc(0.001, decay, 1, -5), doneAction: 2);
			pitchEnv = EnvGen.kr(Env.perc(0.001, 0.07, 62, -8));
			noise = WhiteNoise.ar;
			metallic = Mix(Pulse.ar(
				[4210, 5470, 6250, 7820, 9100, 10300] * toneScale * (1 + randomPitch),
				0.5
			)) / 6;
			voiceSignals = [
				(SinOsc.ar((48 * toneScale * (1 + randomPitch)) + pitchEnv) * 1.2)
					+ (HPF.ar(noise, 5000) * EnvGen.kr(Env.perc(0.001, 0.012)) * 0.13),
				(SinOsc.ar(185 * toneScale * (1 + randomPitch)) * 0.36)
					+ (BPF.ar(noise, 1850 * toneScale, 0.55) * 0.92),
				BPF.ar(noise, 1350 * toneScale, 0.7)
					* (1 + (Pulse.kr(32, 0.35) * 0.35)),
				SinOsc.ar((112 * toneScale * (1 + randomPitch)) + (pitchEnv * 0.35)),
				HPF.ar(metallic + (noise * 0.18), 6100 * toneScale),
				HPF.ar(metallic + (noise * 0.22), 4600 * toneScale)
			];
			signal = SelectX.ar(Clip.kr(voice, 0, 5), voiceSignals);
			driven = (signal * (1 + (driveControl * 7))).tanh;
			Out.ar(out, Pan2.ar(driven * env * amp * voiceLevel));
		}).add;

		SynthDef(\endless303, {
			arg out=0, freq=110, amp=0, sustain=0.18, accent=0, slide=0,
				waveform=0, cutoffControl=0.45, resonanceControl=0.65,
				envMod=0.55, decayControl=0.45, driveControl=0.3,
				slideControl=0.35, t_trig=0;
			var pitch, saw, square, osc, ampEnv, filterEnv, cutoff, rq, signal;
			var accentGain, driveGain;
			pitch = Lag.kr(
				freq,
				Select.kr(slide, [0.002, slideControl.linexp(0, 1, 0.025, 0.22)])
			);
			saw = Saw.ar(pitch);
			square = Pulse.ar(pitch, 0.5);
			osc = SelectX.ar(waveform.clip(0, 1), [saw, square]);
			ampEnv = EnvGen.kr(
				Env.perc(0.003, sustain.max(decayControl.linexp(0, 1, 0.07, 0.8)), 1, -4),
				t_trig
			);
			filterEnv = EnvGen.kr(
				Env.perc(0.002, decayControl.linexp(0, 1, 0.06, 1.2), 1, -5),
				t_trig
			);
			cutoff = (
				cutoffControl.linexp(0, 1, 90, 4200)
				+ (filterEnv * envMod * 7200 * (1 + (accent * 0.65)))
				+ (accent * 650)
			).clip(70, 12000);
			rq = resonanceControl.linlin(0, 1, 0.8, 0.08);
			signal = RLPF.ar(osc, cutoff, rq);
			accentGain = 1 + (accent * 0.45);
			driveGain = driveControl.linexp(0, 1, 1, 12);
			signal = LeakDC.ar((signal * driveGain).tanh) / driveGain.sqrt;
			signal = Limiter.ar(signal * ampEnv * amp * accentGain, 0.85, 0.01);
			Out.ar(out, Pan2.ar(signal));
		}).add;

		SynthDef(\endlessChord, { arg out=0, freq=220, amp=0.5, sustain=0.5, preset=1;
			var env = EnvGen.kr(Env.perc(0.01, sustain.max(0.08), 1, -3), doneAction: 2);
			var detune = Select.kr(preset.clip(1, 4) - 1, #[0.003, 0.008, 0.015, 0.004]);
			var osc = Mix(Saw.ar(freq * [1 - detune, 1, 1 + detune])) / 3;
			var cutoff = Select.kr(preset.clip(1, 4) - 1, #[1200, 3200, 700, 5200]);
			var signal = RLPF.ar(osc, cutoff, 0.3);
			Out.ar(out, Splay.ar(signal * env * amp, 0.35));
		}).add;

		SynthDef(\endlessMono, { arg out=0, freq=220, amp=0.6, sustain=0.2;
			var env = EnvGen.kr(Env.perc(0.004, sustain.max(0.04), 1, -4), doneAction: 2);
			var osc = (Pulse.ar(freq, 0.42) * 0.55) + (Saw.ar(freq * 0.5) * 0.35);
			var signal = RLPF.ar(osc, (freq * 7).clip(250, 8000), 0.24);
			Out.ar(out, Pan2.ar((signal * env * amp).tanh));
		}).add;

		SynthDef(\endlessSampler, { arg out=0, buf=0, amp=0.8, rate=1;
			var signal = PlayBuf.ar(1, buf, BufRateScale.kr(buf) * rate, doneAction: 2);
			Out.ar(out, Pan2.ar(signal * amp));
		}).add;

		server.sync;
		n303Voices = deckBuses.collect({ arg bus;
			Synth.head(context.xg, \endless303, [
				\out, bus.index, \waveform, n303Waveform,
				\cutoffControl, n303Cutoff, \resonanceControl, n303Resonance,
				\envMod, n303EnvMod, \decayControl, n303Decay,
				\driveControl, n303Drive, \slideControl, n303SlideTime
			]);
		});
		deckMixers = deckBuses.collect({ arg bus;
			Synth.tail(context.xg, \endlessDeckMixer, [
				\inBus, bus.index, \out, context.out_b, \level, 1
			]);
		});

		this.addCommand(\deck_level, "if", { arg msg;
			var deck = msg[1].asInteger.clip(1, 2) - 1;
			deckMixers[deck].set(\level, msg[2].asFloat.clip(0, 1));
		});

		this.addCommand(\n808_hit, "iif", { arg msg;
			var deck = msg[1].asInteger.clip(1, 2) - 1;
			var voice = msg[2].asInteger.clip(0, 5);
			var synth;
			if([4, 5].includes(voice), {
				if(openHats[deck].notNil, {
					openHats[deck].free;
					openHats[deck] = nil;
				});
			});
			synth = Synth.head(context.xg, \endless808, [
				\out, deckBuses[deck].index, \voice, voice,
				\amp, msg[3].asFloat.clip(0, 1), \voiceLevel, n808Levels[voice],
				\toneControl, n808Tone, \decayControl, n808Decay,
				\driveControl, n808Drive, \variation, n808Variation
			]);
			voices.add(synth);
			if(voice == 5, {
				openHats[deck] = synth;
				synth.onFree({
					if(openHats[deck] === synth, { openHats[deck] = nil; });
				});
			});
		});

		this.addCommand(\n808_set, "ffff", { arg msg;
			n808Tone = msg[1].asFloat.clip(0, 1);
			n808Decay = msg[2].asFloat.clip(0, 1);
			n808Drive = msg[3].asFloat.clip(0, 1);
			n808Variation = msg[4].asFloat.clip(0, 1);
		});

		this.addCommand(\n808_level, "if", { arg msg;
			var voice = msg[1].asInteger.clip(0, 5);
			n808Levels[voice] = msg[2].asFloat.clip(0, 1.5);
		});

		this.addCommand(\n303_note, "iiffii", { arg msg;
			var deck = msg[1].asInteger.clip(1, 2) - 1;
			var legato = n303SlidePending[deck];
			var controls = [
				\freq, msg[2].asFloat.midicps, \amp, msg[3].asFloat.clip(0, 1),
				\sustain, msg[4].asFloat.clip(1, 16) * 0.12,
				\accent, msg[5].asInteger.clip(0, 1),
				\slide, if(legato, { 1 }, { 0 })
			];
			if(legato.not, { controls = controls ++ [\t_trig, 1]; });
			n303Voices[deck].set(*controls);
			n303SlidePending[deck] = msg[6].asInteger > 0;
		});

		this.addCommand(\n303_set, "fffffff", { arg msg;
			n303Waveform = msg[1].asFloat.clip(0, 1);
			n303Cutoff = msg[2].asFloat.clip(0, 1);
			n303Resonance = msg[3].asFloat.clip(0, 1);
			n303EnvMod = msg[4].asFloat.clip(0, 1);
			n303Decay = msg[5].asFloat.clip(0, 1);
			n303Drive = msg[6].asFloat.clip(0, 1);
			n303SlideTime = msg[7].asFloat.clip(0, 1);
			n303Voices.do({ arg synth;
				synth.set(
					\waveform, n303Waveform, \cutoffControl, n303Cutoff,
					\resonanceControl, n303Resonance, \envMod, n303EnvMod,
					\decayControl, n303Decay, \driveControl, n303Drive,
					\slideControl, n303SlideTime
				);
			});
		});

		this.addCommand(\nchord_note, "iiffi", { arg msg;
			var deck = msg[1].asInteger.clip(1, 2) - 1;
			voices.add(Synth.head(context.xg, \endlessChord, [
				\out, deckBuses[deck].index, \freq, msg[2].asFloat.midicps,
				\amp, msg[3].asFloat, \sustain, msg[4].asFloat * 0.12, \preset, msg[5]
			]));
		});

		this.addCommand(\nmono_note, "iiff", { arg msg;
			var deck = msg[1].asInteger.clip(1, 2) - 1;
			voices.add(Synth.head(context.xg, \endlessMono, [
				\out, deckBuses[deck].index, \freq, msg[2].asFloat.midicps,
				\amp, msg[3].asFloat, \sustain, msg[4].asFloat * 0.12
			]));
		});

		this.addCommand(\nsampler_load, "is", { arg msg;
			var pad = msg[1].asInteger.clip(1, 16) - 1;
			if(sampleBuffers[pad].notNil, { sampleBuffers[pad].free; });
			sampleBuffers[pad] = Buffer.readChannel(server, msg[2].asString, channels: [0]);
		});

		this.addCommand(\nsampler_hit, "iiff", { arg msg;
			var deck = msg[1].asInteger.clip(1, 2) - 1;
			var pad = msg[2].asInteger.clip(1, 16) - 1;
			var buffer = sampleBuffers[pad];
			if(buffer.notNil, {
				voices.add(Synth.head(context.xg, \endlessSampler, [
					\out, deckBuses[deck].index, \buf, buffer.bufnum,
					\amp, msg[3].asFloat, \rate, msg[4].asFloat
				]));
			});
		});

		this.addCommand(\all_off, "", {
			voices.do({ arg synth; synth.free; });
			voices.clear;
			openHats = Array.fill(2, { nil });
			n303SlidePending = Array.fill(2, { false });
			n303Voices.do({ arg synth; synth.set(\amp, 0, \slide, 0); });
		});
	}

	free {
		voices.do({ arg synth; synth.free; });
		n303Voices.do({ arg synth; synth.free; });
		deckMixers.do({ arg synth; synth.free; });
		sampleBuffers.do({ arg buffer; if(buffer.notNil, { buffer.free; }); });
		deckBuses.do({ arg bus; bus.free; });
	}
}
