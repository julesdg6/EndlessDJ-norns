Engine_Endless : CroneEngine {
	var server, deckBuses, deckMixers, voices, sampleBuffers;

	*new { arg context, doneCallback;
		^super.new(context, doneCallback);
	}

	alloc {
		server = context.server;
		voices = List.new;
		sampleBuffers = Array.fill(16, { nil });
		deckBuses = Array.fill(2, { Bus.audio(server, 2) });

		SynthDef(\endlessDeckMixer, { arg inBus=0, level=1;
			var signal = In.ar(inBus, 2);
			Out.ar(Crone.output, signal * Lag.kr(level, 0.03));
		}).add;

		SynthDef(\endless808, { arg out=0, voice=1, amp=0.8;
			var env, pitchEnv, tone, noise, signal;
			env = EnvGen.kr(Env.perc(0.001, Select.kr(voice, #[0.45, 0.22, 0.18, 0.3, 0.08, 0.45, 0.16])), doneAction: 2);
			pitchEnv = EnvGen.kr(Env.perc(0.001, 0.06, 45, -8));
			tone = SinOsc.ar(Select.kr(voice, #[55, 52, 180, 110, 6500, 5200, 190]) + pitchEnv);
			noise = BPF.ar(WhiteNoise.ar, Select.kr(voice, #[900, 1800, 1400, 900, 7800, 6200, 2200]), 0.45);
			signal = SelectX.ar(Clip.kr(voice, 0, 6), [
				tone, (tone * 0.55) + (noise * 0.7), noise, tone,
				HPF.ar(noise, 5500), HPF.ar(noise, 4500), (tone * 0.4) + noise
			]);
			Out.ar(out, Pan2.ar((signal * env * amp).tanh));
		}).add;

		SynthDef(\endless303, { arg out=0, freq=110, amp=0.7, sustain=0.2, accent=0, slide=0;
			var env = EnvGen.kr(Env.perc(0.005, sustain.max(0.04), 1, -4), doneAction: 2);
			var cutoffEnv = EnvGen.kr(Env.perc(0.002, sustain.max(0.08), 4200, -5));
			var osc = Saw.ar(Lag.kr(freq, Select.kr(slide, #[0.002, 0.08])));
			var signal = RLPF.ar(osc, (350 + cutoffEnv + (accent * 1200)).clip(80, 12000), 0.18);
			Out.ar(out, Pan2.ar((signal * env * amp * (1 + (accent * 0.35))).tanh));
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
		deckMixers = deckBuses.collect({ arg bus;
			Synth.tail(server, \endlessDeckMixer, [\inBus, bus.index, \level, 1]);
		});

		this.addCommand(\deck_level, "if", { arg msg;
			var deck = msg[1].asInteger.clip(1, 2) - 1;
			deckMixers[deck].set(\level, msg[2].asFloat.clip(0, 1));
		});

		this.addCommand(\n808_hit, "iif", { arg msg;
			var deck = msg[1].asInteger.clip(1, 2) - 1;
			voices.add(Synth.head(server, \endless808, [
				\out, deckBuses[deck].index, \voice, msg[2].asInteger.clip(0, 6),
				\amp, msg[3].asFloat.clip(0, 1)
			]));
		});

		this.addCommand(\n303_note, "iiffii", { arg msg;
			var deck = msg[1].asInteger.clip(1, 2) - 1;
			var freq = msg[2].asFloat.midicps;
			voices.add(Synth.head(server, \endless303, [
				\out, deckBuses[deck].index, \freq, freq, \amp, msg[3].asFloat,
				\sustain, msg[4].asFloat * 0.12, \accent, msg[5], \slide, msg[6]
			]));
		});

		this.addCommand(\nchord_note, "iiffi", { arg msg;
			var deck = msg[1].asInteger.clip(1, 2) - 1;
			voices.add(Synth.head(server, \endlessChord, [
				\out, deckBuses[deck].index, \freq, msg[2].asFloat.midicps,
				\amp, msg[3].asFloat, \sustain, msg[4].asFloat * 0.12, \preset, msg[5]
			]));
		});

		this.addCommand(\nmono_note, "iiff", { arg msg;
			var deck = msg[1].asInteger.clip(1, 2) - 1;
			voices.add(Synth.head(server, \endlessMono, [
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
				voices.add(Synth.head(server, \endlessSampler, [
					\out, deckBuses[deck].index, \buf, buffer.bufnum,
					\amp, msg[3].asFloat, \rate, msg[4].asFloat
				]));
			});
		});

		this.addCommand(\all_off, "", {
			voices.do({ arg synth; synth.free; });
			voices.clear;
		});
	}

	free {
		voices.do({ arg synth; synth.free; });
		deckMixers.do({ arg synth; synth.free; });
		sampleBuffers.do({ arg buffer; if(buffer.notNil, { buffer.free; }); });
		deckBuses.do({ arg bus; bus.free; });
	}
}
