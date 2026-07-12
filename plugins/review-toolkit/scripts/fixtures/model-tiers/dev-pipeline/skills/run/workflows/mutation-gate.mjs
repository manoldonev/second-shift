const EXECUTOR_MODEL = 'sonnet'
const modelOverrides = (config && config.reviewers && config.reviewers.modelOverrides) || {}
const executorModel = modelOverrides['mutation-executor'] || EXECUTOR_MODEL
const z = agent(prompt, { model: executorModel, label, phase: 'Mutation Gate' })
