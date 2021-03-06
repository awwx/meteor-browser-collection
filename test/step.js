// Generated by CoffeeScript 1.4.0
(function() {
  var StepRunner, _when;

  _when = this.when;

  StepRunner = (function() {

    function StepRunner() {
      this.steps = [];
    }

    StepRunner.prototype.add_step = function(thunk) {
      return this.steps.push(thunk);
    };

    StepRunner.prototype.run_steps = function() {
      var context;
      context = {};
      return when_pipeline(_.map(this.steps, function(step) {
        step = _.bind(step, context);
        return function(arg) {
          return when_timeout(_when.resolve().then(function() {
            return step(arg);
          }), 3000);
        };
      }));
    };

    return StepRunner;

  })();

  this.Stepper = function() {
    var step_runner, stepfn;
    step_runner = new StepRunner();
    stepfn = function(thunk) {
      return step_runner.add_step(thunk);
    };
    stepfn.run = function() {
      return step_runner.run_steps();
    };
    return stepfn;
  };

}).call(this);
