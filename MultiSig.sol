// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

contract MultiSig{
    address[] public owners;
    address public proxyAddress;
    mapping(address => bool) public isOwner;
    uint256 public requiredConfirmations;

    event Confirmation(address indexed sender);
    event Revocation(address indexed sender);
    event Execution(address indexed sender, bool success);

    mapping(uint256 => mapping(address => bool)) public isConfirmed;
    uint256 public transactionCount;
    mapping(uint256 => Transaction) public transactions;

    struct Transaction {
        address destination;
        uint256 value;
        bytes data;
        bool executed;
        uint256 confirmations;
    }

    modifier onlyOwner_() {
        require(isOwner[msg.sender], "Not an owner");
        _;
    }

    modifier notExecuted(uint256 transactionId) {
        require(!transactions[transactionId].executed, "Transaction already executed");
        _;
    }

    modifier confirmed(uint256 transactionId) {
        require(isConfirmed[transactionId][msg.sender], "Transaction not confirmed by sender");
        _;
    }

    modifier notConfirmed(uint256 transactionId) {
        require(!isConfirmed[transactionId][msg.sender], "Transaction already confirmed by sender");
        _;
    }

    modifier validRequirement(uint256 _ownersCount, uint256 _required) {
        require(
            _required <= _ownersCount && _required != 0 && _ownersCount != 0,
            "Invalid requirements"
        );
        _;
    }

    constructor(address[] memory _owners, uint256 _required)
        validRequirement(_owners.length, _required)
    {
        for (uint256 i = 0; i < _owners.length; i++) {
            isOwner[_owners[i]] = true;
        }
        owners = _owners;
        requiredConfirmations = _required;
    }

    function addOwner(address newOwner) external onlyOwner_ {
        isOwner[newOwner] = true;
        owners.push(newOwner);
    }

    function removeOwner(address ownerToRemove) external onlyOwner_ {
        require(owners.length - 1 >= requiredConfirmations, "Removing owner would break confirmations");
        isOwner[ownerToRemove] = false;
        for (uint256 i = 0; i < owners.length; i++) {
            if (owners[i] == ownerToRemove) {
                owners[i] = owners[owners.length - 1];
                owners.pop();
                return;
            }
        }
    }

    function replaceOwner(address ownerToRemove, address newOwner) external onlyOwner_ {
        isOwner[ownerToRemove] = false;
        isOwner[newOwner] = true;
        for (uint256 i = 0; i < owners.length; i++) {
            if (owners[i] == ownerToRemove) {
                owners[i] = newOwner;
                return;
            }
        }
    }

    function confirmTransaction(uint256 transactionId)
        external
        onlyOwner_
        notConfirmed(transactionId)
        notExecuted(transactionId)
    {
        transactions[transactionId].confirmations++;
        isConfirmed[transactionId][msg.sender] = true;
        emit Confirmation(msg.sender);

        if (transactions[transactionId].confirmations >= requiredConfirmations) {
            executeTransaction(transactionId);
        }
    }

    function revokeConfirmation(uint256 transactionId)
        external
        onlyOwner_
        confirmed(transactionId)
        notExecuted(transactionId)
    {
        transactions[transactionId].confirmations--;
        isConfirmed[transactionId][msg.sender] = false;
        emit Revocation(msg.sender);
    }

    function executeTransaction(uint256 transactionId) internal notExecuted(transactionId) {
        require(
            transactions[transactionId].confirmations >= requiredConfirmations,
            "Transaction not yet confirmed"
        );
        transactions[transactionId].executed = true;
        (bool success, ) = transactions[transactionId].destination.call{
            value: transactions[transactionId].value
        }(transactions[transactionId].data);

        emit Execution(msg.sender, success);
    }

    function submitTransaction(address destination, uint256 value, bytes calldata data)
        external
        onlyOwner_
        returns (uint256 transactionId)
    {
        transactionId = transactionCount;
        transactions[transactionId] = Transaction({
            destination: destination,
            value: value,
            data: data,
            executed: false,
            confirmations: 1
        });
        transactionCount++;
        isConfirmed[transactionId][msg.sender] = true;
        emit Confirmation(msg.sender);

        if (transactions[transactionId].confirmations >= requiredConfirmations) {
            executeTransaction(transactionId);
        }
    }
}
    