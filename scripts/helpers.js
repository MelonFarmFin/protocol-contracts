async function sleep(seconds) {
  return new Promise((resolve) => setTimeout(resolve, seconds * 1000));
}

async function deployContract(name, web3, privateKey, abi, bytecodes, params) {
  console.log(`... Deploying ${name}`);

  await sleep(2);

  const deployerAddress = web3.eth.accounts.privateKeyToAccount(privateKey).address;

  const draftContract = new web3.eth.Contract(abi);
  const deployData = draftContract
    .deploy({
      data: bytecodes,
      arguments: params,
    })
    .encodeABI();

  const signedTx = await web3.eth.accounts.signTransaction(
    {
      from: deployerAddress,
      gas: 10000000,
      gasPrice: 1000000,
      data: deployData,
    },
    privateKey,
  );

  try {
    let tx = await web3.eth.sendSignedTransaction(signedTx.rawTransaction);
    return tx.contractAddress;
  } catch (e) {
    console.error(e);
    process.exit(1);
  }
}

module.exports = {
  deployContract,
};
