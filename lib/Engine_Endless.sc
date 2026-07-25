Engine_Endless : CroneEngine {
	var server, deckBuses, deckMixers, voices, sampleBuffers, openHats;
	var n303Voices, n303SlidePending;
	var nmonoVoices;
	var nchordHeld, nchordPreset, nchordBrightness, nchordFilterEnv, nchordChorus;
	var n808Tone=0.5, n808Decay=0.5, n808Drive=0.25, n808Variation=0.15;
	var n808Levels;

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
		nchordHeld = Array.fill(2, { IdentityDictionary.new });
		nchordPreset = Array.fill(2, { 1 });
		nchordBrightness = Array.fill(2, { 0.5 });
		nchordFilterEnv = Array.fill(2, { 0.5 });
		nchordChorus = Array.fill(2, { 0.35 });

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

		SynthDef(\endlessChord, {
			arg out=0, freq=220, amp=0.5, sustain=0.5, preset=1, timed=1,
				gate=1, brightness=0.5, filterEnvAmount=0.5, chorus=0.35;
			var presetIndex, autoGate, envelopeGate, attack, release, env, filterEnv;
			var detune, saw, pulse, organ, digital, signals, osc, cutoff, filtered;
			var dry, wet, output;
			presetIndex = preset.clip(1, 8) - 1;
			autoGate = Line.kr(1, 0, sustain.max(0.03));
			envelopeGate = Select.kr(timed, [gate, autoGate]);
			attack = Select.kr(presetIndex, #[0.004, 0.02, 0.003, 0.35, 0.01, 0.18, 0.015, 0.002]);
			release = Select.kr(presetIndex, #[0.16, 0.75, 0.22, 1.8, 0.35, 1.35, 0.55, 0.12]);
			env = EnvGen.kr(Env.asr(attack, 1, release, -4), envelopeGate, doneAction: 2);
			filterEnv = EnvGen.kr(Env.asr(0.003, 1, release * 0.7, -5), envelopeGate);
			detune = Select.kr(presetIndex, #[0.006, 0.009, 0.018, 0.012, 0.002, 0.007, 0.015, 0.003]);
			saw = Mix(Saw.ar(freq * [1 - detune, 1, 1 + detune])) / 3;
			pulse = Mix(Pulse.ar(freq * [1, 2], [0.48, 0.35], [0.7, 0.3]));
			organ = Mix(SinOsc.ar(freq * [1, 2, 3], 0, [0.65, 0.25, 0.1]));
			digital = (LFTri.ar(freq) * 0.65) + (Pulse.ar(freq * 2, 0.2) * 0.25);
			signals = [
				saw, (saw * 0.75) + (SinOsc.ar(freq * 0.5) * 0.25),
				saw + (Pulse.ar(freq * 1.5, 0.42) * 0.25),
				VarSaw.ar(freq * [0.997, 1.003], 0, 0.55).sum * 0.45,
				organ, (saw * 0.72) + (pulse * 0.28), saw, digital
			];
			osc = SelectX.ar(presetIndex, signals);
			cutoff = (
				brightness.linexp(0, 1, 280, 7200)
				+ (filterEnv * filterEnvAmount * 5000)
			).clip(100, 12000);
			filtered = RLPF.ar(osc, cutoff, 0.28);
			dry = Pan2.ar(filtered);
			wet = [
				DelayC.ar(filtered, 0.03, SinOsc.kr(0.23, 0).range(0.008, 0.022)),
				DelayC.ar(filtered, 0.03, SinOsc.kr(0.19, pi).range(0.009, 0.024))
			];
			output = XFade2.ar(dry, wet, chorus.linlin(0, 1, -1, 1));
			Out.ar(out, Limiter.ar(output * env * amp, 0.85, 0.01));
		}).add;

		SynthDef(\endlessMono, {
			arg out=0, freq=220, amp=0, sustain=0.2, mode=0, gate=0, t_trig=0,
				waveform=0, sub=0.25, cutoffControl=0.55, resonanceControl=0.35,
				attackControl=0.08, releaseControl=0.35, glideControl=0.15,
				lfoRateControl=0.2, lfoDepth=0.08, delaySend=0.15;
			var attack, release, lfoRate, lfo, pitch, osc, subOsc, timedEnv, gatedEnv;
			var env, cutoff, rq, filtered, dry, delayed, output;
			attack = attackControl.linexp(0, 1, 0.002, 0.45);
			release = releaseControl.linexp(0, 1, 0.05, 2.5);
			lfoRate = lfoRateControl.linexp(0, 1, 0.05, 14);
			lfo = SinOsc.kr(lfoRate);
			pitch = Lag.kr(freq, glideControl.linexp(0, 1, 0.002, 0.35))
				* (1 + (lfo * lfoDepth * 0.025));
			osc = SelectX.ar(waveform.clip(0, 2), [
				Saw.ar(pitch), Pulse.ar(pitch, 0.45), LFTri.ar(pitch)
			]);
			subOsc = SinOsc.ar(pitch * 0.5) * sub;
			timedEnv = EnvGen.kr(
				Env.perc(attack, sustain.max(release * 0.35), 1, -4), t_trig
			);
			gatedEnv = EnvGen.kr(Env.asr(attack, 1, release, -4), gate);
			env = Select.kr(mode, [timedEnv, gatedEnv]);
			cutoff = (
				cutoffControl.linexp(0, 1, 120, 9000)
				* (1 + (lfo * lfoDepth * 0.65))
			).clip(80, 12000);
			rq = resonanceControl.linlin(0, 1, 0.9, 0.12);
			filtered = RLPF.ar(osc + subOsc, cutoff, rq);
			dry = Pan2.ar(filtered);
			delayed = [
				CombC.ar(filtered, 0.5, 0.25, 1.6),
				CombC.ar(filtered, 0.5, 0.375, 1.8)
			];
			output = XFade2.ar(dry, delayed, delaySend.linlin(0, 1, -1, 0.65));
			Out.ar(out, Limiter.ar(output * env * amp, 0.82, 0.01));
		}).add;

		SynthDef(\endlessSampler, { arg out=0, buf=0, amp=0.8, rate=1;
			var signal = PlayBuf.ar(1, buf, BufRateScale.kr(buf) * rate, doneAction: 2);
			Out.ar(out, Pan2.ar(signal * amp));
		}).add;

		server.sync;
		n303Voices = deckBuses.collect({ arg bus;
			Synth.head(context.xg, \endless303, [
				\out, bus.index
			]);
		});
		nmonoVoices = deckBuses.collect({ arg bus;
			Synth.head(context.xg, \endlessMono, [\out, bus.index]);
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

		this.addCommand(\n303_set, "ifffffff", { arg msg;
			var deck = msg[1].asInteger.clip(1, 2) - 1;
			n303Voices[deck].set(
				\waveform, msg[2].asFloat.clip(0, 1),
				\cutoffControl, msg[3].asFloat.clip(0, 1),
				\resonanceControl, msg[4].asFloat.clip(0, 1),
				\envMod, msg[5].asFloat.clip(0, 1),
				\decayControl, msg[6].asFloat.clip(0, 1),
				\driveControl, msg[7].asFloat.clip(0, 1),
				\slideControl, msg[8].asFloat.clip(0, 1)
			);
		});

		this.addCommand(\nchord_note, "iiffi", { arg msg;
			var deck = msg[1].asInteger.clip(1, 2) - 1;
			voices.add(Synth.head(context.xg, \endlessChord, [
				\out, deckBuses[deck].index, \freq, msg[2].asFloat.midicps,
				\amp, msg[3].asFloat, \sustain, msg[4].asFloat * 0.12,
				\preset, nchordPreset[deck], \brightness, nchordBrightness[deck],
				\filterEnvAmount, nchordFilterEnv[deck], \chorus, nchordChorus[deck]
			]));
		});

		this.addCommand(\nchord_on, "iifi", { arg msg;
			var deck = msg[1].asInteger.clip(1, 2) - 1;
			var note = msg[2].asInteger.clip(0, 127);
			var synth;
			if(nchordHeld[deck][note].notNil, {
				nchordHeld[deck][note].set(\gate, 0);
			});
			synth = Synth.head(context.xg, \endlessChord, [
				\out, deckBuses[deck].index, \freq, note.midicps,
				\amp, msg[3].asFloat.clip(0, 1), \timed, 0,
				\preset, nchordPreset[deck], \brightness, nchordBrightness[deck],
				\filterEnvAmount, nchordFilterEnv[deck], \chorus, nchordChorus[deck]
			]);
			nchordHeld[deck][note] = synth;
			synth.onFree({
				if(nchordHeld[deck][note] === synth, { nchordHeld[deck].removeAt(note); });
			});
		});

		this.addCommand(\nchord_off, "ii", { arg msg;
			var deck = msg[1].asInteger.clip(1, 2) - 1;
			var note = msg[2].asInteger.clip(0, 127);
			if(nchordHeld[deck][note].notNil, {
				nchordHeld[deck][note].set(\gate, 0);
				nchordHeld[deck].removeAt(note);
			});
		});

		this.addCommand(\nchord_all_off, "i", { arg msg;
			var deck = msg[1].asInteger.clip(1, 2) - 1;
			nchordHeld[deck].do({ arg synth; synth.set(\gate, 0); });
			nchordHeld[deck].clear;
		});

		this.addCommand(\nchord_set, "iifff", { arg msg;
			var deck = msg[1].asInteger.clip(1, 2) - 1;
			nchordPreset[deck] = msg[2].asInteger.clip(1, 8);
			nchordBrightness[deck] = msg[3].asFloat.clip(0, 1);
			nchordFilterEnv[deck] = msg[4].asFloat.clip(0, 1);
			nchordChorus[deck] = msg[5].asFloat.clip(0, 1);
		});

		this.addCommand(\nmono_note, "iiff", { arg msg;
			var deck = msg[1].asInteger.clip(1, 2) - 1;
			nmonoVoices[deck].set(
				\freq, msg[2].asFloat.midicps, \amp, msg[3].asFloat.clip(0, 1),
				\sustain, msg[4].asFloat.clip(1, 32) * 0.12,
				\mode, 0, \gate, 0, \t_trig, 1
			);
		});

		this.addCommand(\nmono_on, "iif", { arg msg;
			var deck = msg[1].asInteger.clip(1, 2) - 1;
			nmonoVoices[deck].set(
				\freq, msg[2].asFloat.midicps, \amp, msg[3].asFloat.clip(0, 1),
				\mode, 1, \gate, 1
			);
		});

		this.addCommand(\nmono_off, "i", { arg msg;
			var deck = msg[1].asInteger.clip(1, 2) - 1;
			nmonoVoices[deck].set(\gate, 0);
		});

		this.addCommand(\nmono_set, "iiffffffffff", { arg msg;
			var deck = msg[1].asInteger.clip(1, 2) - 1;
			nmonoVoices[deck].set(
				\waveform, msg[3].asFloat.clip(0, 2),
				\sub, msg[4].asFloat.clip(0, 1),
				\cutoffControl, msg[5].asFloat.clip(0, 1),
				\resonanceControl, msg[6].asFloat.clip(0, 1),
				\attackControl, msg[7].asFloat.clip(0, 1),
				\releaseControl, msg[8].asFloat.clip(0, 1),
				\glideControl, msg[9].asFloat.clip(0, 1),
				\lfoRateControl, msg[10].asFloat.clip(0, 1),
				\lfoDepth, msg[11].asFloat.clip(0, 1),
				\delaySend, msg[12].asFloat.clip(0, 1)
			);
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
			nmonoVoices.do({ arg synth; synth.set(\amp, 0, \gate, 0); });
			nchordHeld.do({ arg held;
				held.do({ arg synth; synth.set(\gate, 0); });
				held.clear;
			});
		});
	}

	free {
		voices.do({ arg synth; synth.free; });
		n303Voices.do({ arg synth; synth.free; });
		nmonoVoices.do({ arg synth; synth.free; });
		nchordHeld.do({ arg held; held.do({ arg synth; synth.free; }); });
		deckMixers.do({ arg synth; synth.free; });
		sampleBuffers.do({ arg buffer; if(buffer.notNil, { buffer.free; }); });
		deckBuses.do({ arg bus; bus.free; });
	}
}
