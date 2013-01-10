_when = @when

class StepRunner

  constructor: ->
    @steps = []

  add_step: (thunk) ->
    @steps.push(thunk)

  run_steps: ->
    context = {}
    when_pipeline _.map(
      @steps,
      (step) ->
        step = _.bind(step, context)
        (arg) ->
          when_timeout(_when.resolve().then(-> step(arg)), 3000)
    )

@Stepper = ->
  step_runner = new StepRunner()
  stepfn = (thunk) ->
    step_runner.add_step thunk
  stepfn.run = ->
    step_runner.run_steps()
  stepfn
