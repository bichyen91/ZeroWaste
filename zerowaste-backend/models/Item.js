const mongoose = require('mongoose');

const itemSchema = new mongoose.Schema({
  itemCode: { type: String, required: true },
  itemName: { type: String, required: true },
  purchasedDate: { type: String, required: true },
  expiredDate: { type: String },
  createdDate: { type: String, required: true },
  username: { type: String, required: true }
});

module.exports = mongoose.model('Item', itemSchema);
