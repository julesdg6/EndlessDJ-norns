Engine_Endless : CroneEngine {
	var server, deckBuses, instrumentBuses, delayBuses, reverbBuses, masterBus;
	var captureBuses, captureTaps;
	var autoControlBuses, autoMeters;
	var deckMixers, masterMixer, instrumentMixers, effectReturns, voices, sampleBuffers;
	var samplerChokes, samplerHeld, samplerLoops, samplerGrains, openHats;
	var resampleBuffers, resampleRecorders, resamplePlayers;
	var resampleMeterBuses, resampleBufferMeterBuses, resamplePlaybackMeterBuses;
	var resampleAnalyzers;
	var n303Voices, n303SlidePending;
	var nmonoVoices, nbassVoices, nbassGenerations;
	var nchordHeld, nchordPreset, nchordBrightness, nchordFilterEnv, nchordChorus;
	var nchordSynthDefs;
	var delaySends, reverbSends;
	var n808SynthDefs;
	var n808Tone=0.5, n808Decay=0.5, n808Drive=0.25, n808Variation=0.15;
	var n808Levels;

	*new { arg context, doneCallback;
		^super.new(context, doneCallback);
	}

	wakePart { arg deck, part;
		instrumentMixers[deck][part].run(true);
		deckMixers[deck].run(true);
		masterMixer.run(true);
		if(delaySends[deck][part] > 0, { effectReturns[deck][0].run(true); });
		if(reverbSends[deck][part] > 0, { effectReturns[deck][1].run(true); });
	}

	alloc {
		server = context.server;
		voices = List.new;
		sampleBuffers = Array.fill(76, { nil });
		samplerChokes = Array.fill(2, { Array.fill(4, { nil }) });
		samplerHeld = Array.fill(2, { Array.fill(16, { nil }) });
		samplerLoops = Array.fill(2, { Array.fill(16, { nil }) });
		samplerGrains = Array.fill(2, { nil });
		resampleBuffers = Array.fill(2, {
			Buffer.alloc(server, (server.sampleRate * 32).asInteger, 2)
		});
		resampleRecorders = Array.fill(2, { nil });
		resamplePlayers = Array.fill(2, { Array.fill(2, { nil }) });
		resampleMeterBuses = Array.fill(2, { Bus.control(server, 1) });
		resampleBufferMeterBuses = Array.fill(2, { Bus.control(server, 1) });
		resamplePlaybackMeterBuses = Array.fill(2, { Bus.control(server, 1) });
		resampleAnalyzers = Array.fill(2, { nil });
		deckBuses = Array.fill(2, { Bus.audio(server, 2) });
		instrumentBuses = Array.fill(2, {
			Array.fill(5, { Bus.audio(server, 2) })
		});
		delayBuses = Array.fill(2, { Bus.audio(server, 2) });
		reverbBuses = Array.fill(2, { Bus.audio(server, 2) });
		captureBuses = Array.fill(3, { Bus.audio(server, 2) });
		autoControlBuses = Array.fill(2, { Bus.control(server, 2) });
		masterBus = Bus.audio(server, 2);
		openHats = Array.fill(2, { nil });
		n808Levels = Array.fill(6, { 1.0 });
		n808SynthDefs = [
			\endless808Kick, \endless808Snare, \endless808Clap,
			\endless808Tom, \endless808ClosedHat, \endless808OpenHat
		];
		delaySends = Array.fill(2, { Array.fill(5, { 0.0 }) });
		reverbSends = Array.fill(2, { Array.fill(5, { 0.0 }) });
		n303SlidePending = Array.fill(2, { false });
		nchordHeld = Array.fill(2, { IdentityDictionary.new });
		nchordPreset = Array.fill(2, { 1 });
		nchordBrightness = Array.fill(2, { 0.5 });
		nchordFilterEnv = Array.fill(2, { 0.5 });
		nchordChorus = Array.fill(2, { 0.35 });
		nchordSynthDefs = Array.fill(8, { arg preset;
			("endlessChord" ++ (preset + 1)).asSymbol
		});

		SynthDef(\endlessAutoMeter, {
			arg kickBus=0, bassBus=0, outBus=0;
			var kickSignal, bassSignal, kickLevel, bassLevel;
			kickSignal = In.ar(kickBus, 2);
			bassSignal = In.ar(bassBus, 2);
			kickLevel = Amplitude.kr(
				kickSignal[0].abs + kickSignal[1].abs, 0.005, 0.12
			).clip(0, 1);
			bassLevel = Amplitude.kr(
				bassSignal[0].abs + bassSignal[1].abs, 0.01, 0.16
			).clip(0, 1);
			ReplaceOut.kr(outBus, [kickLevel, bassLevel]);
		}).add;

		SynthDef(\endlessInstrumentMixer, {
			arg inBus=0, outBus=0, delayBus=0, reverbBus=0,
				autoBus=0, part=0,
				level=1, pan=0, filterControl=1, saturation=0,
				delaySend=0, reverbSend=0, autoAmount=0,
				kickDuck=0.3, melodyPriority=0.45;
			var input, cutoff, filtered, saturated, driven, signal, saturationAmount;
			var autoLevels, kickLevel, bassLevel, sidechain, roleGain;
			input = In.ar(inBus, 2);
			cutoff = filterControl.linexp(0, 1, 180, 20000);
			filtered = LPF.ar(input, Lag.kr(cutoff, 0.03));
			saturationAmount = Lag.kr(saturation, 0.03);
			saturated = (filtered * (1 + (saturationAmount * 5))).tanh;
			driven = (filtered * (1 - saturationAmount)) +
				(saturated * saturationAmount);
			signal = Balance2.ar(
				driven[0], driven[1], Lag.kr(pan, 0.03), Lag.kr(level, 0.03)
			);
			autoLevels = In.kr(autoBus, 2);
			kickLevel = autoLevels[0];
			bassLevel = autoLevels[1];
			sidechain = kickLevel.max(bassLevel);
			roleGain = Select.kr(part, [
				1,
				(1 - (kickLevel * kickDuck * autoAmount * 0.45)).clip(0.6, 1),
				(1 - (
					sidechain * autoAmount * (0.62 - (melodyPriority * 0.32))
				)).clip(0.55, 1),
				(1 - (
					sidechain * autoAmount * (0.52 - (melodyPriority * 0.28))
				)).clip(0.6, 1),
				(1 - (sidechain * autoAmount * 0.28)).clip(0.7, 1)
			]);
			signal = signal * Lag.kr(roleGain, 0.04);
			Out.ar(outBus, signal);
			Out.ar(delayBus, signal * Lag.kr(delaySend, 0.03));
			Out.ar(reverbBus, signal * Lag.kr(reverbSend, 0.03));
		}).add;

		SynthDef(\endlessDelayReturn, { arg inBus=0, out=0, level=0.7;
			var input, delayed;
			input = In.ar(inBus, 2);
			delayed = [
				CombC.ar(input[0] + (input[1] * 0.2), 0.75, 0.375, 2.2),
				CombC.ar(input[1] + (input[0] * 0.2), 0.75, 0.5, 2.4)
			];
			delayed = LeakDC.ar(delayed) * 0.45 * Lag.kr(level, 0.03);
			Out.ar(out, delayed);
			DetectSilence.ar(
				delayed[0].abs + delayed[1].abs + Impulse.ar(0), 0.0001, 1.0, doneAction: 1
			);
		}).add;

		SynthDef(\endlessReverbReturn, { arg inBus=0, out=0, level=0.7;
			var input, wet;
			input = In.ar(inBus, 2);
			wet = FreeVerb2.ar(input[0], input[1], 0.78, 0.72, 0.35);
			wet = LeakDC.ar(wet) * 0.42 * Lag.kr(level, 0.03);
			Out.ar(out, wet);
			DetectSilence.ar(wet[0].abs + wet[1].abs + Impulse.ar(0), 0.0001, 1.0, doneAction: 1);
		}).add;

		SynthDef(\endlessDeckMixer, { arg inBus=0, out=0, level=1;
			var signal;
			signal = In.ar(inBus, 2) * Lag.kr(level, 0.03);
			Out.ar(out, signal);
		}).add;

		SynthDef(\endlessCaptureTap, { arg inBus=0, outBus=0;
			Out.ar(outBus, In.ar(inBus, 2));
		}).add;

		SynthDef(\endlessMaster, {
			arg inBus=0, out=0, masterLevel=0.9, limiterCeiling=0.9,
				compression=0.35, threshold=0.55;
			var signal, controlled;
			signal = In.ar(inBus, 2);
			controlled = Compander.ar(
				signal, signal, Lag.kr(threshold, 0.03), 1,
				1 - (Lag.kr(compression, 0.03) * 0.75), 0.01, 0.12
			);
			Out.ar(
				out,
				Limiter.ar(
					LeakDC.ar(controlled) * Lag.kr(masterLevel, 0.03),
					Lag.kr(limiterCeiling, 0.03), 0.01
				)
			);
		}).add;

		SynthDef(\endless808Kick, {
			arg out=0, amp=0.8, voiceLevel=1, toneControl=0.5,
				decayControl=0.5, driveControl=0.25, variation=0.15;
			var decay, toneScale, randomPitch, env, pitchEnv, click, signal;
			decay = 0.48 * decayControl.linexp(0, 1, 0.45, 1.8);
			toneScale = toneControl.linexp(0, 1, 0.65, 1.55);
			randomPitch = Rand(-1.0, 1.0) * variation * 0.045;
			env = EnvGen.kr(Env.perc(0.001, decay, 1, -5), doneAction: 2);
			pitchEnv = EnvGen.kr(Env.perc(0.001, 0.07, 62, -8));
			click = HPF.ar(WhiteNoise.ar, 5000)
				* EnvGen.kr(Env.perc(0.001, 0.012)) * 0.13;
			signal = (SinOsc.ar(
				(48 * toneScale * (1 + randomPitch)) + pitchEnv
			) * 1.2) + click;
			signal = (signal * (1 + (driveControl * 7))).tanh;
			Out.ar(out, Pan2.ar(signal * env * amp * voiceLevel));
		}).add;

		SynthDef(\endless808Snare, {
			arg out=0, amp=0.8, voiceLevel=1, toneControl=0.5,
				decayControl=0.5, driveControl=0.25, variation=0.15;
			var decay, toneScale, randomPitch, env, signal;
			decay = 0.24 * decayControl.linexp(0, 1, 0.45, 1.8);
			toneScale = toneControl.linexp(0, 1, 0.65, 1.55);
			randomPitch = Rand(-1.0, 1.0) * variation * 0.045;
			env = EnvGen.kr(Env.perc(0.001, decay, 1, -5), doneAction: 2);
			signal = (SinOsc.ar(185 * toneScale * (1 + randomPitch)) * 0.36)
				+ (BPF.ar(WhiteNoise.ar, 1850 * toneScale, 0.55) * 0.92);
			signal = (signal * (1 + (driveControl * 7))).tanh;
			Out.ar(out, Pan2.ar(signal * env * amp * voiceLevel));
		}).add;

		SynthDef(\endless808Clap, {
			arg out=0, amp=0.8, voiceLevel=1, toneControl=0.5,
				decayControl=0.5, driveControl=0.25, variation=0.15;
			var decay, toneScale, env, signal;
			decay = 0.20 * decayControl.linexp(0, 1, 0.45, 1.8);
			toneScale = toneControl.linexp(0, 1, 0.65, 1.55);
			env = EnvGen.kr(Env.perc(0.001, decay, 1, -5), doneAction: 2);
			signal = BPF.ar(WhiteNoise.ar, 1350 * toneScale, 0.7)
				* (1 + (Pulse.kr(32, 0.35) * 0.35));
			signal = (signal * (1 + (driveControl * 7))).tanh;
			Out.ar(out, Pan2.ar(signal * env * amp * voiceLevel));
		}).add;

		SynthDef(\endless808Tom, {
			arg out=0, amp=0.8, voiceLevel=1, toneControl=0.5,
				decayControl=0.5, driveControl=0.25, variation=0.15;
			var decay, toneScale, randomPitch, env, pitchEnv, signal;
			decay = 0.32 * decayControl.linexp(0, 1, 0.45, 1.8);
			toneScale = toneControl.linexp(0, 1, 0.65, 1.55);
			randomPitch = Rand(-1.0, 1.0) * variation * 0.045;
			env = EnvGen.kr(Env.perc(0.001, decay, 1, -5), doneAction: 2);
			pitchEnv = EnvGen.kr(Env.perc(0.001, 0.07, 62, -8));
			signal = SinOsc.ar(
				(112 * toneScale * (1 + randomPitch)) + (pitchEnv * 0.35)
			);
			signal = (signal * (1 + (driveControl * 7))).tanh;
			Out.ar(out, Pan2.ar(signal * env * amp * voiceLevel));
		}).add;

		SynthDef(\endless808ClosedHat, {
			arg out=0, amp=0.8, voiceLevel=1, toneControl=0.5,
				decayControl=0.5, driveControl=0.25, variation=0.15;
			var decay, toneScale, randomPitch, env, metallic, signal;
			decay = 0.075 * decayControl.linexp(0, 1, 0.45, 1.8);
			toneScale = toneControl.linexp(0, 1, 0.65, 1.55);
			randomPitch = Rand(-1.0, 1.0) * variation * 0.045;
			env = EnvGen.kr(Env.perc(0.001, decay, 1, -5), doneAction: 2);
			metallic = Mix(Pulse.ar(
				[4210, 5470, 6250, 7820, 9100, 10300] * toneScale * (1 + randomPitch),
				0.5
			)) / 6;
			signal = HPF.ar(metallic + (WhiteNoise.ar * 0.18), 6100 * toneScale);
			signal = (signal * (1 + (driveControl * 7))).tanh;
			Out.ar(out, Pan2.ar(signal * env * amp * voiceLevel));
		}).add;

		SynthDef(\endless808OpenHat, {
			arg out=0, amp=0.8, voiceLevel=1, toneControl=0.5,
				decayControl=0.5, driveControl=0.25, variation=0.15;
			var decay, toneScale, randomPitch, env, metallic, signal;
			decay = 0.55 * decayControl.linexp(0, 1, 0.45, 1.8);
			toneScale = toneControl.linexp(0, 1, 0.65, 1.55);
			randomPitch = Rand(-1.0, 1.0) * variation * 0.045;
			env = EnvGen.kr(Env.perc(0.001, decay, 1, -5), doneAction: 2);
			metallic = Mix(Pulse.ar(
				[4210, 5470, 6250, 7820, 9100, 10300] * toneScale * (1 + randomPitch),
				0.5
			)) / 6;
			signal = HPF.ar(metallic + (WhiteNoise.ar * 0.22), 4600 * toneScale);
			signal = (signal * (1 + (driveControl * 7))).tanh;
			Out.ar(out, Pan2.ar(signal * env * amp * voiceLevel));
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
			signal = Pan2.ar(signal);
			Out.ar(out, signal);
		}).add;

		8.do({ arg presetIndex;
			SynthDef(nchordSynthDefs[presetIndex], {
				arg out=0, freq=220, amp=0.5, sustain=0.5, timed=1,
					gate=1, brightness=0.5, filterEnvAmount=0.5, chorus=0.35;
				var autoGate, envelopeGate, attack, release, env, filterEnv;
				var detune, osc, cutoff, filtered, dry, wet, output;
				autoGate = Line.kr(1, 0, sustain.max(0.03));
				envelopeGate = Select.kr(timed, [gate, autoGate]);
				attack = #[0.004, 0.02, 0.003, 0.35, 0.01, 0.18, 0.015, 0.002][presetIndex];
				release = #[0.16, 0.75, 0.22, 1.8, 0.35, 1.35, 0.55, 0.12][presetIndex];
				detune = #[0.006, 0.009, 0.018, 0.012, 0.002, 0.007, 0.015, 0.003][presetIndex];
				env = EnvGen.kr(
					Env.asr(attack, 1, release, -4), envelopeGate, doneAction: 2
				);
				filterEnv = EnvGen.kr(
					Env.asr(0.003, 1, release * 0.7, -5), envelopeGate
				);
				osc = switch(presetIndex,
					0, {
						Mix(Saw.ar(freq * [1 - detune, 1, 1 + detune])) / 3
					},
					1, {
						(Mix(Saw.ar(freq * [1 - detune, 1, 1 + detune])) / 3 * 0.75)
							+ (SinOsc.ar(freq * 0.5) * 0.25)
					},
					2, {
						(Mix(Saw.ar(freq * [1 - detune, 1, 1 + detune])) / 3)
							+ (Pulse.ar(freq * 1.5, 0.42) * 0.25)
					},
					3, {
						VarSaw.ar(freq * [0.997, 1.003], 0, 0.55).sum * 0.45
					},
					4, {
						Mix(SinOsc.ar(freq * [1, 2, 3], 0, [0.65, 0.25, 0.1]))
					},
					5, {
						(Mix(Saw.ar(freq * [1 - detune, 1, 1 + detune])) / 3 * 0.72)
							+ (Mix(Pulse.ar(
								freq * [1, 2], [0.48, 0.35], [0.7, 0.3]
							)) * 0.28)
					},
					6, {
						Mix(Saw.ar(freq * [1 - detune, 1, 1 + detune])) / 3
					},
					7, {
						(LFTri.ar(freq) * 0.65) + (Pulse.ar(freq * 2, 0.2) * 0.25)
					}
				);
				cutoff = (
					brightness.linexp(0, 1, 280, 7200)
					+ (filterEnv * filterEnvAmount * 5000)
				).clip(100, 12000);
				filtered = RLPF.ar(osc, cutoff, 0.28);
				dry = Pan2.ar(filtered);
				wet = [
					DelayC.ar(
						filtered, 0.03, SinOsc.kr(0.23, 0).range(0.008, 0.022)
					),
					DelayC.ar(
						filtered, 0.03, SinOsc.kr(0.19, pi).range(0.009, 0.024)
					)
				];
				output = XFade2.ar(dry, wet, chorus.linlin(0, 1, -1, 1));
				Out.ar(out, Limiter.ar(output * env * amp, 0.85, 0.01));
			}).add;
		});

		SynthDef(\endlessMono, {
			arg out=0, freq=220, amp=0, sustain=0.2, mode=0, gate=0, t_trig=0,
				model=0,
				waveform=0, sub=0.25, cutoffControl=0.55, resonanceControl=0.35,
				attackControl=0.08, releaseControl=0.35, glideControl=0.15,
				lfoRateControl=0.2, lfoDepth=0.08, delaySend=0.15;
			var attack, release, lfoRate, lfo, pitch, analog, subVoice, reese;
			var organ, fm, wobble, osc, subOsc, timedEnv, gatedEnv;
			var env, cutoff, rq, filtered, dry, delayed, output;
			attack = attackControl.linexp(0, 1, 0.002, 0.45);
			release = releaseControl.linexp(0, 1, 0.05, 2.5);
			lfoRate = lfoRateControl.linexp(0, 1, 0.05, 14);
			lfo = SinOsc.kr(lfoRate);
			pitch = Lag.kr(freq, glideControl.linexp(0, 1, 0.002, 0.35))
				* (1 + (lfo * lfoDepth * 0.025));
			analog = SelectX.ar(waveform.clip(0, 2), [
				Saw.ar(pitch), Pulse.ar(pitch, 0.45), LFTri.ar(pitch)
			]);
			subVoice = (SinOsc.ar(pitch) * 0.78) + (LFTri.ar(pitch * 0.5) * 0.22);
			reese = Mix.ar(Saw.ar(pitch * [0.985, 0.995, 1.005, 1.015])) * 0.28;
			organ = Mix.ar(Pulse.ar(
				pitch * [0.5, 1, 2, 3], [0.5, 0.46, 0.38, 0.3],
				[0.22, 0.42, 0.23, 0.13]
			));
			fm = SinOsc.ar(
				pitch,
				SinOsc.ar(pitch * (2 + (lfoDepth * 2)))
					* lfoDepth.linlin(0, 1, 0.25, 8)
			);
			wobble = Mix.ar(VarSaw.ar(
				pitch * [0.5, 1], 0, lfo.range(0.08, 0.92), [0.48, 0.52]
			));
			osc = SelectX.ar(model.clip(0, 5), [
				analog, subVoice, reese, organ, fm, wobble
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
			output = Limiter.ar(output * env * amp, 0.82, 0.01);
			Out.ar(out, output);
		}).add;

		SynthDef(\endlessSampler, {
			arg out=0, buf=0, amp=0.8, rate=1, pan=0, start=0, finish=1,
				cutoffControl=1, gate=1, timed=1, repeatDelay=0;
			var frames, reverse, startFrame, duration, play;
			var repeated, autoGate, envelopeGate, env, cutoff, signal;
			frames = BufFrames.kr(buf);
			reverse = rate < 0;
			startFrame = Select.kr(reverse, [start * frames, finish * frames]);
			duration = ((finish - start).abs * BufDur.kr(buf) / rate.abs.max(0.01)).max(0.01);
			play = PlayBuf.ar(
				1, buf, BufRateScale.kr(buf) * rate, startPos: startFrame,
				doneAction: 0
			);
			repeated = Select.ar(repeatDelay > 0, [
				play,
				play + DelayN.ar(play, 0.5, repeatDelay.clip(0.01, 0.5))
			]);
			autoGate = Line.kr(1, 0, duration + repeatDelay.clip(0, 0.5));
			envelopeGate = Select.kr(timed, [gate, autoGate]);
			env = EnvGen.kr(Env.asr(0.003, 1, 0.03), envelopeGate, doneAction: 2);
			cutoff = cutoffControl.linexp(0, 1, 180, 18000);
			signal = LPF.ar(repeated, cutoff);
			Out.ar(out, Pan2.ar(signal * amp * env, pan));
		}).add;

		SynthDef(\endlessSamplerLoop, {
			arg out=0, buf=0, amp=0.8, rate=1, pan=0, start=0, finish=1,
				cutoffControl=1, gate=1;
			var frames, startFrame, endFrame, phase, play, env, cutoff, signal;
			frames = BufFrames.kr(buf);
			startFrame = start.clip(0, 0.99) * frames;
			endFrame = finish.clip(0.01, 1) * frames;
			phase = Phasor.ar(
				0, BufRateScale.kr(buf) * rate.abs.max(0.01),
				startFrame, endFrame.max(startFrame + 2), startFrame
			);
			play = BufRd.ar(1, buf, phase, loop: 1, interpolation: 4);
			env = EnvGen.kr(Env.asr(0.01, 1, 0.04), gate, doneAction: 2);
			cutoff = cutoffControl.linexp(0, 1, 180, 18000);
			signal = LPF.ar(play, cutoff);
			Out.ar(out, Pan2.ar(signal * amp * env, pan));
		}).add;

		SynthDef(\endlessSamplerGrain, {
			arg out=0, buf=0, amp=0.65, position=0.5, grainSize=0.12,
				density=12, rate=1, pan=0, spread=0.6, cutoffControl=1,
				freeze=0, gate=1;
			var scan, grainPosition, trigger, grainPan, signal, env, cutoff;
			scan = LFSaw.kr(
				rate.abs.max(0.05) / BufDur.kr(buf).max(0.05),
				position.linlin(0, 1, -1, 1)
			).range(0.01, 0.99);
			grainPosition = Select.kr(freeze.clip(0, 1), [
				scan,
				position.clip(0.01, 0.99)
			]);
			trigger = Impulse.kr(density.clip(1, 32));
			grainPan = (pan + LFNoise1.kr(density.clip(1, 32))
				.range(spread.neg, spread)).clip(-1, 1);
			signal = GrainBuf.ar(
				2, trigger, grainSize.clip(0.015, 0.5), buf,
				rate.clip(-4, 4), grainPosition, 2, grainPan,
				envbufnum: -1, maxGrains: 24
			);
			env = EnvGen.kr(Env.asr(0.04, 1, 0.12), gate, doneAction: 2);
			cutoff = cutoffControl.linexp(0, 1, 180, 18000);
			Out.ar(out, Limiter.ar(LPF.ar(signal, cutoff) * amp * env, 0.9, 0.01));
		}).add;

		SynthDef(\endlessResampleRecord, {
			arg inBus=0, buf=0, meterBus=0, duration=1;
			var input, peak, stop;
			input = In.ar(inBus, 2);
			peak = PeakFollower.kr(
				(input[0].abs + input[1].abs).clip(0, 2), 0.9999
			);
			ReplaceOut.kr(meterBus, peak);
			RecordBuf.ar(input, buf, recLevel: 1, preLevel: 0, loop: 0);
			stop = Line.kr(0, 1, duration.clip(0.1, 32), doneAction: 2);
		}).add;

		SynthDef(\endlessResamplePlayer, {
			arg out=0, buf=0, amp=0.8, rate=1, start=0, finish=1,
				meterBus=0, gate=1;
			var frames, startFrame, signal, duration, env, output;
			frames = BufFrames.kr(buf);
			startFrame = start.clip(0, 0.99) * frames;
			signal = PlayBuf.ar(
				2, buf, BufRateScale.kr(buf) * rate,
				startPos: startFrame, loop: 0
			);
			duration = (
				(finish - start).abs * BufDur.kr(buf) / rate.abs.max(0.01)
			).max(0.01);
			env = EnvGen.kr(Env.linen(0.005, duration, 0.04), doneAction: 2);
			output = signal * amp * env;
			ReplaceOut.kr(
				meterBus,
				PeakFollower.kr((output[0].abs + output[1].abs).clip(0, 2), 0.9999)
			);
			Out.ar(out, output);
		}).add;

		SynthDef(\endlessResampleLoop, {
			arg out=0, buf=0, amp=0.8, rate=1, start=0, meterBus=0, gate=1;
			var startFrame, signal, env, output;
			startFrame = start.clip(0, 0.99) * BufFrames.kr(buf);
			signal = PlayBuf.ar(
				2, buf, BufRateScale.kr(buf) * rate,
				startPos: startFrame, loop: 1
			);
			env = EnvGen.kr(Env.asr(0.005, 1, 0.04), gate, doneAction: 2);
			output = signal * amp * env;
			ReplaceOut.kr(
				meterBus,
				PeakFollower.kr((output[0].abs + output[1].abs).clip(0, 2), 0.9999)
			);
			Out.ar(out, output);
		}).add;

		SynthDef(\endlessResampleAnalyze, {
			arg buf=0, meterBus=0, finish=0.0625;
			var signal, duration, peak;
			signal = PlayBuf.ar(2, buf, BufRateScale.kr(buf), loop: 0);
			peak = PeakFollower.kr(
				(signal[0].abs + signal[1].abs).clip(0, 2), 0.9999
			);
			ReplaceOut.kr(meterBus, peak);
			duration = (BufDur.kr(buf) * finish.clip(0.001, 1)).max(0.05);
			Line.kr(0, 1, duration, doneAction: 2);
		}).add;

		SynthDef(\endlessResampleGrain, {
			arg out=0, buf=0, amp=0.65, position=0.5, grainSize=0.12,
				density=12, rate=1, spread=0.6, cutoffControl=1,
				finish=1, freeze=0, gate=1;
			var recordedDuration, scan, grainPosition, trigger, pan, signal, env;
			recordedDuration = (BufDur.kr(buf) * finish.clip(0.01, 1)).max(0.05);
			scan = LFSaw.kr(
				rate.abs.max(0.05) / recordedDuration,
				position.linlin(0, 1, -1, 1)
			).range(0.005, finish.clip(0.01, 1));
			grainPosition = Select.kr(freeze.clip(0, 1), [
				scan,
				position.clip(0.005, 0.995) * finish.clip(0.01, 1)
			]);
			trigger = Impulse.kr(density.clip(1, 24));
			pan = LFNoise1.kr(density.clip(1, 24)).range(spread.neg, spread);
			signal = GrainBuf.ar(
				2, trigger, grainSize.clip(0.02, 0.4), buf,
				rate.clip(-2, 2), grainPosition, 2, pan,
				envbufnum: -1, maxGrains: 16
			);
			env = EnvGen.kr(Env.asr(0.04, 1, 0.12), gate, doneAction: 2);
			signal = LPF.ar(signal, cutoffControl.linexp(0, 1, 180, 18000));
			Out.ar(out, Limiter.ar(signal * amp * env, 0.85, 0.01));
		}).add;

		server.sync;
		n303Voices = Array.fill(2, { arg deck;
			Synth.head(context.xg, \endless303, [
				\out, instrumentBuses[deck][1].index
			]);
		});
		nmonoVoices = Array.fill(2, { arg deck;
			Synth.head(context.xg, \endlessMono, [
				\out, instrumentBuses[deck][3].index
			]);
		});
		nbassGenerations = Array.fill(2, { 0 });
		nbassVoices = Array.fill(2, { arg deck;
			var synth = Synth.head(context.xg, \endlessMono, [
				\out, instrumentBuses[deck][1].index
			]);
			synth.run(false);
			synth
		});
		autoMeters = Array.fill(2, { arg deck;
			Synth.tail(context.xg, \endlessAutoMeter, [
				\kickBus, instrumentBuses[deck][0].index,
				\bassBus, instrumentBuses[deck][1].index,
				\outBus, autoControlBuses[deck].index
			]);
		});
		instrumentMixers = Array.fill(2, { arg deck;
			Array.fill(5, { arg part;
				Synth.tail(context.xg, \endlessInstrumentMixer, [
					\inBus, instrumentBuses[deck][part].index,
					\outBus, deckBuses[deck].index,
					\delayBus, delayBuses[deck].index,
					\reverbBus, reverbBuses[deck].index,
					\autoBus, autoControlBuses[deck].index,
					\part, part
				]);
			});
		});
		effectReturns = Array.fill(2, { arg deck;
			[
				Synth.tail(context.xg, \endlessDelayReturn, [
					\inBus, delayBuses[deck].index, \out, deckBuses[deck].index
				]),
				Synth.tail(context.xg, \endlessReverbReturn, [
					\inBus, reverbBuses[deck].index, \out, deckBuses[deck].index
				])
			]
		});
		captureTaps = deckBuses.collect({ arg bus, deck;
			Synth.tail(context.xg, \endlessCaptureTap, [
				\inBus, bus.index, \outBus, captureBuses[deck].index
			]);
		});
		deckMixers = deckBuses.collect({ arg bus;
			Synth.tail(context.xg, \endlessDeckMixer, [
				\inBus, bus.index, \out, masterBus.index, \level, 1
			]);
		});
		captureTaps = captureTaps.add(
			Synth.tail(context.xg, \endlessCaptureTap, [
				\inBus, masterBus.index, \outBus, captureBuses[2].index
			])
		);
		masterMixer = Synth.tail(context.xg, \endlessMaster, [
			\inBus, masterBus.index, \out, context.out_b
		]);

		this.addCommand(\deck_level, "if", { arg msg;
			var deck = msg[1].asInteger.clip(1, 2) - 1;
			if(msg[2].asFloat > 0, {
				deckMixers[deck].run(true);
				masterMixer.run(true);
			});
			deckMixers[deck].set(\level, msg[2].asFloat.clip(0, 1));
		});

		this.addCommand(\mixer_set, "iiffffff", { arg msg;
			var deck = msg[1].asInteger.clip(1, 2) - 1;
			var part = msg[2].asInteger.clip(1, 5) - 1;
			delaySends[deck][part] = msg[7].asFloat.clip(0, 1);
			reverbSends[deck][part] = msg[8].asFloat.clip(0, 1);
			if(delaySends[deck][part] > 0, {
				effectReturns[deck][0].run(true);
				deckMixers[deck].run(true);
				masterMixer.run(true);
			});
			if(reverbSends[deck][part] > 0, {
				effectReturns[deck][1].run(true);
				deckMixers[deck].run(true);
				masterMixer.run(true);
			});
			instrumentMixers[deck][part].set(
				\level, msg[3].asFloat.clip(0, 1.5),
				\pan, msg[4].asFloat.clip(-1, 1),
				\filterControl, msg[5].asFloat.clip(0, 1),
				\saturation, msg[6].asFloat.clip(0, 1),
				\delaySend, msg[7].asFloat.clip(0, 1),
				\reverbSend, msg[8].asFloat.clip(0, 1)
			);
		});

		this.addCommand(\fx_return_set, "iff", { arg msg;
			var deck = msg[1].asInteger.clip(1, 2) - 1;
			effectReturns[deck][0].set(\level, msg[2].asFloat.clip(0, 1.5));
			effectReturns[deck][1].set(\level, msg[3].asFloat.clip(0, 1.5));
		});

		this.addCommand(\automix_set, "ifff", { arg msg;
			var deck = msg[1].asInteger.clip(1, 2) - 1;
			instrumentMixers[deck].do({ arg mixer;
				mixer.set(
					\autoAmount, msg[2].asFloat.clip(0, 1),
					\kickDuck, msg[3].asFloat.clip(0, 1),
					\melodyPriority, msg[4].asFloat.clip(0, 1)
				);
			});
		});

		this.addCommand(\master_set, "ffff", { arg msg;
			masterMixer.set(
				\masterLevel, msg[1].asFloat.clip(0, 1.25),
				\limiterCeiling, msg[2].asFloat.clip(0.5, 0.98),
				\compression, msg[3].asFloat.clip(0, 1),
				\threshold, msg[4].asFloat.clip(0.2, 1)
			);
		});

		this.addCommand(\n808_hit, "iif", { arg msg;
			var deck = msg[1].asInteger.clip(1, 2) - 1;
			var voice = msg[2].asInteger.clip(0, 5);
			var synth;
			this.wakePart(deck, 0);
			if([4, 5].includes(voice), {
				if(openHats[deck].notNil, {
					openHats[deck].free;
					openHats[deck] = nil;
				});
			});
			synth = Synth.head(context.xg, n808SynthDefs[voice], [
				\out, instrumentBuses[deck][0].index,
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
			this.wakePart(deck, 1);
			n303Voices[deck].set(*controls);
			n303Voices[deck].run(true);
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
			this.wakePart(deck, 2);
			voices.add(Synth.head(
				context.xg, nchordSynthDefs[nchordPreset[deck] - 1], [
				\out, instrumentBuses[deck][2].index, \freq, msg[2].asFloat.midicps,
				\amp, msg[3].asFloat, \sustain, msg[4].asFloat * 0.12,
				\brightness, nchordBrightness[deck],
				\filterEnvAmount, nchordFilterEnv[deck], \chorus, nchordChorus[deck]
			]));
		});

		this.addCommand(\nchord_on, "iifi", { arg msg;
			var deck = msg[1].asInteger.clip(1, 2) - 1;
			var note = msg[2].asInteger.clip(0, 127);
			var synth;
			this.wakePart(deck, 2);
			if(nchordHeld[deck][note].notNil, {
				nchordHeld[deck][note].set(\gate, 0);
			});
			synth = Synth.head(
				context.xg, nchordSynthDefs[nchordPreset[deck] - 1], [
				\out, instrumentBuses[deck][2].index, \freq, note.midicps,
				\amp, msg[3].asFloat.clip(0, 1), \timed, 0,
				\brightness, nchordBrightness[deck],
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
			this.wakePart(deck, 3);
			nmonoVoices[deck].set(
				\freq, msg[2].asFloat.midicps, \amp, msg[3].asFloat.clip(0, 1),
				\sustain, msg[4].asFloat.clip(1, 32) * 0.12,
				\mode, 0, \gate, 0, \t_trig, 1
			);
			nmonoVoices[deck].run(true);
		});

		this.addCommand(\nmono_on, "iif", { arg msg;
			var deck = msg[1].asInteger.clip(1, 2) - 1;
			this.wakePart(deck, 3);
			nmonoVoices[deck].set(
				\freq, msg[2].asFloat.midicps, \amp, msg[3].asFloat.clip(0, 1),
				\mode, 1, \gate, 1
			);
			nmonoVoices[deck].run(true);
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

		this.addCommand(\nmono_model, "ii", { arg msg;
			var deck = msg[1].asInteger.clip(1, 2) - 1;
			nmonoVoices[deck].set(\model, msg[2].asInteger.clip(0, 5));
		});

		this.addCommand(\nbass_note, "iiff", { arg msg;
			var deck = msg[1].asInteger.clip(1, 2) - 1;
			var generation;
			this.wakePart(deck, 1);
			nbassGenerations[deck] = nbassGenerations[deck] + 1;
			generation = nbassGenerations[deck];
			nbassVoices[deck].set(
				\freq, msg[2].asFloat.midicps, \amp, msg[3].asFloat.clip(0, 1),
				\sustain, msg[4].asFloat.clip(1, 32) * 0.12,
				\mode, 0, \gate, 0, \t_trig, 1
			);
			nbassVoices[deck].run(true);
			SystemClock.sched((msg[4].asFloat.clip(1, 32) * 0.12) + 2.6, {
				if(nbassGenerations[deck] == generation, {
					nbassVoices[deck].run(false);
				});
				nil
			});
		});

		this.addCommand(\nbass_set, "iiffffffffff", { arg msg;
			var deck = msg[1].asInteger.clip(1, 2) - 1;
			nbassVoices[deck].set(
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

		this.addCommand(\nbass_model, "ii", { arg msg;
			var deck = msg[1].asInteger.clip(1, 2) - 1;
			nbassVoices[deck].set(\model, msg[2].asInteger.clip(0, 5));
		});

		this.addCommand(\nsampler_load, "is", { arg msg;
			var pad = msg[1].asInteger.clip(1, 76) - 1;
			if(sampleBuffers[pad].notNil, { sampleBuffers[pad].free; });
			sampleBuffers[pad] = Buffer.readChannel(server, msg[2].asString, channels: [0]);
		});

		this.addCommand(\nsampler_hit, "iiffffffi", { arg msg;
			var deck = msg[1].asInteger.clip(1, 2) - 1;
			var pad = msg[2].asInteger.clip(1, 76) - 1;
			var buffer = sampleBuffers[pad];
			var choke = msg[9].asInteger.clip(0, 4);
			if(buffer.notNil, {
				var synth;
				this.wakePart(deck, 4);
				if(choke > 0 and: { samplerChokes[deck][choke - 1].notNil }, {
					samplerChokes[deck][choke - 1].set(\gate, 0);
				});
				synth = Synth.head(context.xg, \endlessSampler, [
					\out, instrumentBuses[deck][4].index, \buf, buffer.bufnum,
					\amp, msg[3].asFloat.clip(0, 1.5),
					\rate, msg[4].asFloat.clip(-4, 4),
					\pan, msg[5].asFloat.clip(-1, 1),
					\start, msg[6].asFloat.clip(0, 1),
					\finish, msg[7].asFloat.clip(0, 1),
					\cutoffControl, msg[8].asFloat.clip(0, 1)
				]);
				voices.add(synth);
				if(choke > 0, { samplerChokes[deck][choke - 1] = synth; });
			});
		});

		this.addCommand(\nsampler_repeat, "iiffffffif", { arg msg;
			var deck = msg[1].asInteger.clip(1, 2) - 1;
			var pad = msg[2].asInteger.clip(1, 76) - 1;
			var buffer = sampleBuffers[pad];
			var choke = msg[9].asInteger.clip(0, 4);
			if(buffer.notNil, {
				var synth;
				this.wakePart(deck, 4);
				if(choke > 0 and: { samplerChokes[deck][choke - 1].notNil }, {
					samplerChokes[deck][choke - 1].set(\gate, 0);
				});
				synth = Synth.head(context.xg, \endlessSampler, [
					\out, instrumentBuses[deck][4].index, \buf, buffer.bufnum,
					\amp, msg[3].asFloat.clip(0, 1.5),
					\rate, msg[4].asFloat.clip(-4, 4),
					\pan, msg[5].asFloat.clip(-1, 1),
					\start, msg[6].asFloat.clip(0, 1),
					\finish, msg[7].asFloat.clip(0, 1),
					\cutoffControl, msg[8].asFloat.clip(0, 1),
					\repeatDelay, msg[10].asFloat.clip(0.01, 0.5)
				]);
				voices.add(synth);
				if(choke > 0, { samplerChokes[deck][choke - 1] = synth; });
			});
		});

		this.addCommand(\nsampler_on, "iiffffffi", { arg msg;
			var deck = msg[1].asInteger.clip(1, 2) - 1;
			var pad = msg[2].asInteger.clip(1, 16) - 1;
			var buffer = sampleBuffers[pad];
			var choke = msg[9].asInteger.clip(0, 4);
			if(buffer.notNil, {
				var synth;
				this.wakePart(deck, 4);
				if(samplerHeld[deck][pad].notNil, {
					samplerHeld[deck][pad].set(\gate, 0);
				});
				if(choke > 0 and: { samplerChokes[deck][choke - 1].notNil }, {
					samplerChokes[deck][choke - 1].set(\gate, 0);
				});
				synth = Synth.head(context.xg, \endlessSampler, [
					\out, instrumentBuses[deck][4].index, \buf, buffer.bufnum,
					\amp, msg[3].asFloat.clip(0, 1.5),
					\rate, msg[4].asFloat.clip(-4, 4),
					\pan, msg[5].asFloat.clip(-1, 1),
					\start, msg[6].asFloat.clip(0, 1),
					\finish, msg[7].asFloat.clip(0, 1),
					\cutoffControl, msg[8].asFloat.clip(0, 1),
					\timed, 0, \gate, 1
				]);
				voices.add(synth);
				samplerHeld[deck][pad] = synth;
				if(choke > 0, { samplerChokes[deck][choke - 1] = synth; });
			});
		});

		this.addCommand(\nsampler_off, "ii", { arg msg;
			var deck = msg[1].asInteger.clip(1, 2) - 1;
			var pad = msg[2].asInteger.clip(1, 16) - 1;
			if(samplerHeld[deck][pad].notNil, {
				samplerHeld[deck][pad].set(\gate, 0);
				samplerHeld[deck][pad] = nil;
			});
		});

		this.addCommand(\nsampler_loop_on, "iiffffff", { arg msg;
			var deck = msg[1].asInteger.clip(1, 2) - 1;
			var pad = msg[2].asInteger.clip(1, 16) - 1;
			var buffer = sampleBuffers[pad];
			if(buffer.notNil, {
				var synth;
				this.wakePart(deck, 4);
				if(samplerLoops[deck][pad].notNil, {
					samplerLoops[deck][pad].set(\gate, 0);
				});
				synth = Synth.head(context.xg, \endlessSamplerLoop, [
					\out, instrumentBuses[deck][4].index, \buf, buffer.bufnum,
					\amp, msg[3].asFloat.clip(0, 1.5),
					\rate, msg[4].asFloat.clip(0.125, 8),
					\pan, msg[5].asFloat.clip(-1, 1),
					\start, msg[6].asFloat.clip(0, 0.99),
					\finish, msg[7].asFloat.clip(0.01, 1),
					\cutoffControl, msg[8].asFloat.clip(0, 1)
				]);
				voices.add(synth);
				samplerLoops[deck][pad] = synth;
			});
		});

		this.addCommand(\nsampler_loop_off, "ii", { arg msg;
			var deck = msg[1].asInteger.clip(1, 2) - 1;
			var pad = msg[2].asInteger.clip(1, 16) - 1;
			if(samplerLoops[deck][pad].notNil, {
				samplerLoops[deck][pad].set(\gate, 0);
				samplerLoops[deck][pad] = nil;
			});
		});

		this.addCommand(\nsampler_grain_on, "iiffffffffi", { arg msg;
			var deck = msg[1].asInteger.clip(1, 2) - 1;
			var pad = msg[2].asInteger.clip(1, 16) - 1;
			var buffer = sampleBuffers[pad];
			if(buffer.notNil, {
				this.wakePart(deck, 4);
				if(samplerGrains[deck].notNil, {
					samplerGrains[deck].set(\gate, 0);
				});
				samplerGrains[deck] = Synth.head(context.xg, \endlessSamplerGrain, [
					\out, instrumentBuses[deck][4].index, \buf, buffer.bufnum,
					\amp, msg[3].asFloat.clip(0, 1.25),
					\position, msg[4].asFloat.clip(0, 1),
					\grainSize, msg[5].asFloat.clip(0.015, 0.5),
					\density, msg[6].asFloat.clip(1, 32),
					\rate, msg[7].asFloat.clip(-4, 4),
					\pan, msg[8].asFloat.clip(-1, 1),
					\spread, msg[9].asFloat.clip(0, 1),
					\cutoffControl, msg[10].asFloat.clip(0, 1),
					\freeze, msg[11].asInteger.clip(0, 1)
				]);
				voices.add(samplerGrains[deck]);
			});
		});

		this.addCommand(\nsampler_grain_off, "i", { arg msg;
			var deck = msg[1].asInteger.clip(1, 2) - 1;
			if(samplerGrains[deck].notNil, {
				samplerGrains[deck].set(\gate, 0);
				samplerGrains[deck] = nil;
			});
		});

		this.addCommand(\resample_start, "iif", { arg msg;
			var source = msg[1].asInteger.clip(1, 3) - 1;
			var slot = msg[2].asInteger.clip(1, 2) - 1;
			var sourceBus = captureBuses[source].index;
			var sourceNode = captureTaps[source];
			if(resampleRecorders[slot].notNil, {
				resampleRecorders[slot].free;
			});
			deckMixers.do({ arg mixer; mixer.run(true); });
			masterMixer.run(true);
			// Read the current block after the selected deck/master mixer has
			// consumed its source bus. This keeps capture ordering explicit and
			// avoids relying on feedback-bus behaviour for an ordinary tap.
			resampleRecorders[slot] = Synth.after(sourceNode, \endlessResampleRecord, [
				\inBus, sourceBus, \buf, resampleBuffers[slot].bufnum,
				\meterBus, resampleMeterBuses[slot].index,
				\duration, msg[3].asFloat.clip(0.1, 32)
			]);
		});

		this.addPoll("resample_record_peak_1", {
			resampleMeterBuses[0].getSynchronous;
		});
		this.addPoll("resample_record_peak_2", {
			resampleMeterBuses[1].getSynchronous;
		});
		this.addPoll("resample_buffer_peak_1", {
			resampleBufferMeterBuses[0].getSynchronous;
		});
		this.addPoll("resample_buffer_peak_2", {
			resampleBufferMeterBuses[1].getSynchronous;
		});
		this.addPoll("resample_playback_peak_1", {
			resamplePlaybackMeterBuses[0].getSynchronous;
		});
		this.addPoll("resample_playback_peak_2", {
			resamplePlaybackMeterBuses[1].getSynchronous;
		});

		this.addCommand(\resample_record_stop, "i", { arg msg;
			var slot = msg[1].asInteger.clip(1, 2) - 1;
			if(resampleRecorders[slot].notNil, {
				resampleRecorders[slot].free;
				resampleRecorders[slot] = nil;
			});
		});

		this.addCommand(\resample_analyze, "if", { arg msg;
			var slot = msg[1].asInteger.clip(1, 2) - 1;
			if(resampleAnalyzers[slot].notNil, {
				resampleAnalyzers[slot].free;
			});
			resampleAnalyzers[slot] = Synth.tail(
				context.xg, \endlessResampleAnalyze, [
					\buf, resampleBuffers[slot].bufnum,
					\meterBus, resampleBufferMeterBuses[slot].index,
					\finish, msg[2].asFloat.clip(0.001, 1)
				]
			);
		});

		this.addCommand(\resample_play, "iiiffff", { arg msg;
			var deck = msg[1].asInteger.clip(1, 2) - 1;
			var slot = msg[2].asInteger.clip(1, 2) - 1;
			var mode = msg[3].asInteger.clip(1, 3);
			if(resamplePlayers[deck][slot].notNil, {
				resamplePlayers[deck][slot].set(\gate, 0);
			});
			deckMixers[deck].run(true);
			masterMixer.run(true);
			resamplePlayers[deck][slot] = Synth.head(
				context.xg,
				if(mode == 2, { \endlessResampleLoop }, { \endlessResamplePlayer }),
				[
					\out, deckBuses[deck].index,
					\buf, resampleBuffers[slot].bufnum,
					\amp, msg[4].asFloat.clip(0, 1.25),
					\rate, msg[5].asFloat.clip(0.25, 2),
					\start, msg[6].asFloat.clip(0, 0.99),
					\finish, msg[7].asFloat.clip(0.01, 1),
					\meterBus, resamplePlaybackMeterBuses[slot].index
				]
			);
			voices.add(resamplePlayers[deck][slot]);
		});

		this.addCommand(\resample_grain_on, "iiffffffffi", { arg msg;
			var deck = msg[1].asInteger.clip(1, 2) - 1;
			var slot = msg[2].asInteger.clip(1, 2) - 1;
			if(resamplePlayers[deck][slot].notNil, {
				resamplePlayers[deck][slot].set(\gate, 0);
			});
			deckMixers[deck].run(true);
			masterMixer.run(true);
			resamplePlayers[deck][slot] = Synth.head(
				context.xg, \endlessResampleGrain, [
					\out, deckBuses[deck].index,
					\buf, resampleBuffers[slot].bufnum,
					\amp, msg[3].asFloat.clip(0, 1.25),
					\position, msg[4].asFloat.clip(0, 1),
					\grainSize, msg[5].asFloat.clip(0.02, 0.4),
					\density, msg[6].asFloat.clip(1, 24),
					\rate, msg[7].asFloat.clip(-2, 2),
					\spread, msg[8].asFloat.clip(0, 1),
					\cutoffControl, msg[9].asFloat.clip(0, 1),
					\finish, msg[10].asFloat.clip(0.01, 1),
					\freeze, msg[11].asInteger.clip(0, 1)
				]
			);
			voices.add(resamplePlayers[deck][slot]);
		});

		this.addCommand(\resample_stop, "ii", { arg msg;
			var deck = msg[1].asInteger.clip(1, 2) - 1;
			var slot = msg[2].asInteger.clip(1, 2) - 1;
			if(resamplePlayers[deck][slot].notNil, {
				resamplePlayers[deck][slot].set(\gate, 0);
				resamplePlayers[deck][slot] = nil;
			});
		});

		this.addCommand(\all_off, "", {
			voices.do({ arg synth; synth.free; });
			voices.clear;
			openHats = Array.fill(2, { nil });
			samplerChokes = Array.fill(2, { Array.fill(4, { nil }) });
			samplerHeld = Array.fill(2, { Array.fill(16, { nil }) });
			samplerLoops = Array.fill(2, { Array.fill(16, { nil }) });
			samplerGrains = Array.fill(2, { nil });
			resampleRecorders.do({ arg synth; if(synth.notNil, { synth.free; }); });
			resampleRecorders = Array.fill(2, { nil });
			resamplePlayers = Array.fill(2, { Array.fill(2, { nil }) });
			n303SlidePending = Array.fill(2, { false });
			nbassGenerations = nbassGenerations.collect({ arg generation; generation + 1; });
			n303Voices.do({ arg synth; synth.set(\amp, 0, \slide, 0); });
			nmonoVoices.do({ arg synth; synth.set(\amp, 0, \gate, 0); });
			nbassVoices.do({ arg synth; synth.set(\amp, 0, \gate, 0); });
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
		nbassVoices.do({ arg synth; synth.free; });
		nchordHeld.do({ arg held; held.do({ arg synth; synth.free; }); });
		resampleRecorders.do({ arg synth; if(synth.notNil, { synth.free; }); });
		resampleAnalyzers.do({ arg synth; if(synth.notNil, { synth.free; }); });
		autoMeters.do({ arg synth; synth.free; });
		instrumentMixers.do({ arg deck; deck.do({ arg synth; synth.free; }); });
		effectReturns.do({ arg deck; deck.do({ arg synth; synth.free; }); });
		captureTaps.do({ arg synth; synth.free; });
		deckMixers.do({ arg synth; synth.free; });
		masterMixer.free;
		sampleBuffers.do({ arg buffer; if(buffer.notNil, { buffer.free; }); });
		resampleBuffers.do({ arg buffer; buffer.free; });
		resampleMeterBuses.do({ arg bus; bus.free; });
		resampleBufferMeterBuses.do({ arg bus; bus.free; });
		resamplePlaybackMeterBuses.do({ arg bus; bus.free; });
		instrumentBuses.do({ arg deck; deck.do({ arg bus; bus.free; }); });
		autoControlBuses.do({ arg bus; bus.free; });
		delayBuses.do({ arg bus; bus.free; });
		reverbBuses.do({ arg bus; bus.free; });
		captureBuses.do({ arg bus; bus.free; });
		deckBuses.do({ arg bus; bus.free; });
		masterBus.free;
	}
}
