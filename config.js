module.exports = {
  token: process.env.GITHUB_COM_TOKEN,
  hostRules: [
    {
      hostType: 'maven',
      matchHost: process.env.CI_SERVER_HOST,
      token: process.env.RENOVATE_TOKEN,
    },
    {
      hostType: 'docker',
      matchHost: process.env.CI_REGISTRY,
      username: 'ci',
      password: process.env.RENOVATE_TOKEN,
    },
  ],
  registryAliases:{
    "$CI_REGISTRY": process.env.CI_REGISTRY,
    "$CI_SERVER_FQDN": process.env.CI_SERVER_FQDN,
    "$CI_SERVER_HOST": process.env.CI_SERVER_FQDN
  },
  forkProcessing: 'enabled',
  platformAutomerge: true,
  autodiscover: true,
  allowScripts: true,
  exposeAllEnv: true,
  persistRepoData: true
};
