// npm install merkletreejs keccak256 ethers fs
const { MerkleTree } = require('merkletreejs');
const keccak256 = require('keccak256');
const fs = require('fs');

// Example: load JSON like [{ "address": "0xabc...", "amount": "100000000000000000000" }, ...]
const list = JSON.parse(fs.readFileSync('./allowlist.json', 'utf8'));

// create leaves: keccak256(abi.encodePacked(address, amount))
// IMPORTANT: amount must be a decimal string of the token amount in wei (include token decimals)
const leaves = list.map(item => {
  // make sure lowercase checksum consistent
  const addr = item.address.toLowerCase();
  const amt = item.amount.toString(); // already in wei
  // use solidity packed encoding equivalent: keccak256(abi.encodePacked(addr, amt))
  // merkletreejs with keccak256 on Buffer of concatenated address + amount as hex
  // simplest: use ethers.utils.solidityKeccak256 on (address, uint256), but for dependency minimal:
  const leaf = require('ethers').utils.solidityKeccak256(['address','uint256'], [addr, amt]);
  return Buffer.from(leaf.slice(2), 'hex');
});

const tree = new MerkleTree(leaves, keccak256, { sortPairs: true });
const root = '0x' + tree.getRoot().toString('hex');
console.log('merkle root:', root);

// produce proof for each address and save to a file
const output = list.map((item, idx) => {
  const leaf = leaves[idx];
  const proof = tree.getProof(leaf).map(x => '0x' + x.data.toString('hex'));
  return {
    address: item.address,
    amount: item.amount,
    proof
  };
});
fs.writeFileSync('./proofs.json', JSON.stringify({ root, proofs: output }, null, 2));
console.log('wrote proofs.json');
