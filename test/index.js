const aptos = require('aptos');
const axios = require('axios');

const NODE_URL = "https://fullnode.devnet.aptoslabs.com";
const FAUCET_URL = "https://faucet.devnet.aptoslabs.com";

const client = new aptos.AptosClient(NODE_URL);
const faucetClient = new aptos.FaucetClient(NODE_URL, FAUCET_URL);

const aptosCoin = "0x1::coin::CoinStore<0x1::aptos_coin::AptosCoin>";
const resource = "0x7d687d919979339a197d9a7311c4f7510cf5764b0499edfff77675dfe320da37";
const contract = `${resource}::duels`;

const roundNumber = 1;
const bet = 10000;


let owner, player1, player2;

async function initialize() {
  owner = new aptos.HexString(resource);
  player1 = new aptos.AptosAccount();
  player2 = new aptos.AptosAccount();

  await faucetClient.fundAccount(owner, 100_000_000);
  await faucetClient.fundAccount(player1.address(), 100_000_000);
  await faucetClient.fundAccount(player2.address(), 100_000_000);

  console.log("Owner at the start");
  await getBalance(owner);

  createRound();
}

async function createRound() {
  let payload = {
    function: `${contract}::create_round`,
    type_arguments: [],
    arguments: [bet, false]
  };
  await sendTxn(payload, player1);
  await getBalance(player1.address());
  getRoundInfo();
  enterRound();
};

async function enterRound() {
  let payload = {
    function: `${contract}::enter_round`,
    type_arguments: [],
    arguments: [bet, roundNumber]
  };
  await sendTxn(payload, player2);
  await getBalance(player2.address());
  getRoundInfo();
  endRound();
}

async function endRound() {
  console.log("Owner before");
  await getBalance(owner);

  let payload = {
    function: `${contract}::end_round`,
    type_arguments: [],
    arguments: [roundNumber]
  };
  await sendTxn(payload, player1);

  await getBalance(player1.address());
  await getBalance(player2.address());

  console.log("Owner After");
  await getBalance(owner);

  getRoundInfo();
}

async function getRoundInfo() {
  let result = await axios.post('https://fullnode.devnet.aptoslabs.com/v1/view', {
      "function": `${contract}::get_round_info`,
      "type_arguments": [],
      "arguments": [`${roundNumber}`]
  });
  console.log(result.data);
}

async function getBalance(account) {
  let resources = await client.getAccountResources(account);
  let accountResource = resources.find((item) => item.type === aptosCoin);
  console.log(`${account} \nBalance = ${accountResource.data.coin.value}`);
}

async function sendTxn(payload, account) {
  const txnRequest = await client.generateTransaction(account.address(), payload);
  const signedTxn = await client.signTransaction(account, txnRequest);
  const transactionRes = await client.submitTransaction(signedTxn);
  return await client.waitForTransaction(transactionRes.hash);
}

initialize();