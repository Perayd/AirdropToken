// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/*
  AirdropToken
  - Fixed total supply: 10,000 tokens (18 decimals)
  - Owner can set a Merkle root for an allowlist airdrop
  - Users can claim their allocation with a Merkle proof
  - Owner can also perform a direct batch airdrop (owner-only)
  - Uses OpenZeppelin-style implementations (we inline small versions to keep single file)
*/

/// @dev Minimal interface of ERC20 events/transfer
interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
}

library MerkleProof {
    // verifies a Merkle proof for a leaf in a tree with given root
    function verify(bytes32[] memory proof, bytes32 root, bytes32 leaf) internal pure returns (bool) {
        bytes32 computed = leaf;
        for (uint i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];
            if (computed <= proofElement) {
                computed = keccak256(abi.encodePacked(computed, proofElement));
            } else {
                computed = keccak256(abi.encodePacked(proofElement, computed));
            }
        }
        return computed == root;
    }
}

contract AirdropToken is IERC20 {
    string public name = "AirdropToken";
    string public symbol = "ADROP";
    uint8  public decimals = 18;

    uint256 private _totalSupply;
    address public owner;

    mapping(address => uint256) private _balances;

    // Merkle root for allowlist claims
    bytes32 public merkleRoot;

    // track claims to prevent double-claiming
    mapping(address => bool) public hasClaimed;

    // events
    event OwnerChanged(address indexed oldOwner, address indexed newOwner);
    event MerkleRootUpdated(bytes32 indexed newRoot);
    event Claimed(address indexed claimant, uint256 amount);
    event AirdropBatch(uint256 count);

    modifier onlyOwner() {
        require(msg.sender == owner, "only owner");
        _;
    }

    constructor() {
        owner = msg.sender;
        // total supply = 10,000 * 10^decimals
        _totalSupply = 10000 * 10 ** uint256(decimals);
        // assign entire supply to owner at deploy
        _balances[owner] = _totalSupply;
        emit Transfer(address(0), owner, _totalSupply);
    }

    // ERC20 read methods
    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }
    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    // Simple transfer (no allowances implemented for brevity, add if you want)
    function transfer(address to, uint256 amount) external override returns (bool) {
        require(to != address(0), "transfer to zero");
        require(_balances[msg.sender] >= amount, "insufficient balance");
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    // ---- Owner utility ----

    /// @notice set a new Merkle root (owner only)
    function setMerkleRoot(bytes32 newRoot) external onlyOwner {
        merkleRoot = newRoot;
        emit MerkleRootUpdated(newRoot);
    }

    /// @notice change owner
    function changeOwner(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero owner");
        address old = owner;
        owner = newOwner;
        emit OwnerChanged(old, newOwner);
    }

    /// @notice owner-only batch airdrop: sends tokens from owner balance to a list
    /// @dev amounts must be in token wei (i.e., include decimals)
    function airdropBatch(address[] calldata recipients, uint256[] calldata amounts) external onlyOwner {
        require(recipients.length == amounts.length, "length mismatch");
        uint256 len = recipients.length;
        for (uint i = 0; i < len; i++) {
            address to = recipients[i];
            uint256 amt = amounts[i];
            require(to != address(0), "airdrop to zero");
            require(_balances[owner] >= amt, "owner balance low");
            _balances[owner] -= amt;
            _balances[to] += amt;
            emit Transfer(owner, to, amt);
        }
        emit AirdropBatch(len);
    }

    // ---- Merkle-claim airdrop ----

    /// @notice Claim allocation with merkle proof
    /// @param amount the amount expected (in token wei)
    /// @param proof merkle proof for the leaf: keccak256(abi.encodePacked(address, amount))
    function claim(uint256 amount, bytes32[] calldata proof) external {
        require(!hasClaimed[msg.sender], "already claimed");
        require(merkleRoot != bytes32(0), "merkle root not set");
        // build leaf and verify
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, amount));
        require(MerkleProof.verify(proof, merkleRoot, leaf), "invalid proof");

        // mark claimed and transfer from owner pool
        hasClaimed[msg.sender] = true;

        require(_balances[owner] >= amount, "insufficient owner reserve");
        _balances[owner] -= amount;
        _balances[msg.sender] += amount;
        emit Transfer(owner, msg.sender, amount);
        emit Claimed(msg.sender, amount);
    }

    // ---- Emergency / utilities ----

    /// @notice Owner can withdraw tokens from contract address (if any)
    function withdrawTokens(address to, uint256 amount) external onlyOwner {
        require(to != address(0), "zero to");
        require(_balances[address(this)] >= amount, "contract balance low");
        _balances[address(this)] -= amount;
        _balances[to] += amount;
        emit Transfer(address(this), to, amount);
    }
}
