const mongoose = require('mongoose');

const userSchema = new mongoose.Schema({
  username: { type: String, required: true, unique: true },
  password: { type: String, required: true },
  alert_day: { type: Number, default: 3 },
  alert_time: { type: String, default: "08:00" }
});

module.exports = mongoose.model('User', userSchema);
