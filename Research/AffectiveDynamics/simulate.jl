#!/usr/bin/env julia

# EVA affective-dynamics research harness.
#
# This intentionally uses only Julia's standard library. It lets us tune and
# stress-test the same leaky state model used by the Swift app without shipping
# a Julia runtime inside EVA.app. Later iterations can replace the hand-authored
# event sequence with anonymized evaluation transcripts and parameter search.

using Printf

Base.@kwdef mutable struct Affect
    valence::Float64 = 0.16
    arousal::Float64 = 0.25
    anxiety::Float64 = 0.13
    energy::Float64 = 0.44
    trust::Float64 = 0.42
    closeness::Float64 = 0.22
    curiosity::Float64 = 0.56
    playfulness::Float64 = 0.30
end

Base.@kwdef struct Appraisal
    positive::Float64 = 0.0
    negative::Float64 = 0.0
    threat::Float64 = 0.0
    uncertainty::Float64 = 0.0
    warmth::Float64 = 0.0
    hostility::Float64 = 0.0
    apology::Float64 = 0.0
    playful::Float64 = 0.0
    disclosure::Float64 = 0.0
    novelty::Float64 = 0.0
    intensity::Float64 = 0.0
end

const BASELINE = Affect()

relaxed(current, baseline, elapsed, tau) =
    baseline + (current - baseline) * exp(-elapsed / tau)

function relax!(state::Affect, elapsed_seconds::Real)
    elapsed = max(Float64(elapsed_seconds), 0.0)
    state.valence = relaxed(state.valence, BASELINE.valence, elapsed, 21_600)
    state.arousal = relaxed(state.arousal, BASELINE.arousal, elapsed, 900)
    state.anxiety = relaxed(state.anxiety, BASELINE.anxiety, elapsed, 2_700)
    state.energy = relaxed(state.energy, BASELINE.energy, elapsed, 7_200)
    state.curiosity = relaxed(state.curiosity, BASELINE.curiosity, elapsed, 10_800)
    state.playfulness = relaxed(state.playfulness, BASELINE.playfulness, elapsed, 5_400)
    # Absence alone must not lower trust or closeness.
    return state
end

function observe!(state::Affect, a::Appraisal)
    state.valence += 0.24a.positive - 0.27a.negative - 0.12a.hostility + 0.06a.warmth + 0.06a.apology
    state.arousal += 0.15a.intensity + 0.12a.threat + 0.07a.playful
    state.anxiety += 0.30a.threat + 0.16a.uncertainty + 0.10a.hostility - 0.08a.positive - 0.10a.apology
    state.energy += 0.14a.positive + 0.08a.playful - 0.13a.negative - 0.06a.threat
    state.trust += 0.018a.warmth + 0.012a.disclosure + 0.020a.apology - 0.035a.hostility
    state.closeness += 0.010a.warmth + 0.008a.disclosure + 0.008a.apology - 0.018a.hostility
    state.curiosity += 0.10a.novelty - 0.04a.negative
    state.playfulness += 0.18a.playful + 0.06a.positive - 0.16a.negative - 0.18a.threat
    for field in fieldnames(Affect)
        value = getfield(state, field)
        lower = field == :valence ? -1.0 : 0.0
        setfield!(state, field, clamp(value, lower, 1.0))
    end
    return state
end

function row(label, minute, state)
    @printf("%-22s %7.1f  %+7.3f  %7.3f  %7.3f  %7.3f  %7.3f  %7.3f\n",
        label, minute, state.valence, state.arousal, state.anxiety,
        state.energy, state.trust, state.closeness)
end

function main()
    state = Affect()
    initial_trust = state.trust
    initial_closeness = state.closeness

    println("event                    minute  valence  arousal  anxiety   energy    trust closeness")
    row("baseline", 0, state)

    observe!(state, Appraisal(positive=0.5, negative=0.35, intensity=0.2, novelty=0.4))
    row("promotion + loneliness", 1, state)

    relax!(state, 120)
    observe!(state, Appraisal(threat=0.5, uncertainty=1.0, intensity=0.6))
    peak_anxiety = state.anxiety
    row("uncertain threat", 3, state)

    relax!(state, 600)
    observe!(state, Appraisal(warmth=0.5, apology=0.5))
    row("safety + repair", 13, state)

    relax!(state, 3_600)
    row("one hour later", 73, state)

    @assert 0.0 <= state.anxiety <= 1.0
    @assert state.anxiety < peak_anxiety

    trust_before_absence = state.trust
    closeness_before_absence = state.closeness
    relax!(state, 60 * 60 * 24 * 30)
    row("after 30-day absence", 43_273, state)
    @assert state.trust == trust_before_absence
    @assert state.closeness == closeness_before_absence
    @assert state.trust >= initial_trust
    @assert state.closeness >= initial_closeness

    println("\nAll affective-dynamics invariants passed.")
end

main()
