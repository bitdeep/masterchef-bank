const Multicall = artifacts.require("Multicall");
// truffle migrate --f 8 --to 8 --network dev
module.exports = function(deployer) {
  deployer.deploy(Multicall);
};
