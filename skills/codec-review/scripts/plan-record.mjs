#!/usr/bin/env node
// Updates the plan-review mod's review record (plans/.codec-reviewed.json) for one plan.
//
//   node plan-record.mjs <renew|reviewed|remove> <plan-path> <sha256-of-the-original-plan>
//
// renew    - push the entry's lease 20 minutes ahead (start of every round)
// reviewed - the review converged or deadlocked: the same content is never re-reviewed
// remove   - the run aborted: the next approval of this plan requests a review again
//
// Prints one word: renewed | marked-reviewed | removed | no-record | locked.
// "no-record" (exit 0) means plan-review did not start this review (or is not
// installed, or runs where it keeps no record) - there is nothing to update.
// "locked" (exit 2) means another process held the record's lock for ~10 s.
// The lock and lease format match the mod's sentinel.ps1.
import { openSync, writeSync, closeSync, readFileSync, writeFileSync, renameSync, unlinkSync, statSync, existsSync } from 'node:fs'
import { dirname, join } from 'node:path'

const [action, planPath, hash] = process.argv.slice(2)
if (!['renew', 'reviewed', 'remove'].includes(action) || !planPath || !/^[0-9a-f]{64}$/i.test(hash ?? '')) {
  console.error('usage: node plan-record.mjs <renew|reviewed|remove> <plan-path> <sha256>')
  process.exit(64)
}
const key = hash.toLowerCase()
const folder = dirname(planPath)
const recordPath = join(folder, '.codec-reviewed.json')
const lockPath = join(folder, '.codec-sentinel.lock')
if (!existsSync(recordPath)) { console.log('no-record'); process.exit(0) }

const sleep = ms => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms)
const minutesFromNow = m => new Date(Date.now() + m * 60000).toISOString()

function staleLock() {
  try {
    const lease = JSON.parse(readFileSync(lockPath, 'utf8').replace(/^\uFEFF/, '')).lease_until
    if (!lease || !Number.isFinite(Date.parse(lease))) throw new Error('no lease')
    return Date.parse(lease) <= Date.now()
  } catch {
    // An unreadable fresh lock may still be receiving its lease bytes.
    try { return statSync(lockPath).mtimeMs <= Date.now() - 2 * 60000 } catch { return false }
  }
}

function acquire() {
  for (let attempt = 0; attempt < 40; attempt++) {
    try {
      const fd = openSync(lockPath, 'wx')
      writeSync(fd, JSON.stringify({ pid: process.pid, lease_until: minutesFromNow(2) }))
      closeSync(fd)
      return true
    } catch (error) {
      if (error.code !== 'EEXIST') throw error
      if (staleLock()) { try { unlinkSync(lockPath) } catch {} continue }
      sleep(250)
    }
  }
  return false
}

// Returns the word to print; writes the record only when something changes.
function update() {
  const record = JSON.parse(readFileSync(recordPath, 'utf8').replace(/^\uFEFF/, ''))
  if (record === null || typeof record !== 'object' || Array.isArray(record)) throw new Error('Review record must be a JSON object.')
  const entry = record[key]
  if (entry === undefined || entry === null || typeof entry !== 'object') return 'no-record'
  let word
  if (action === 'remove') {
    delete record[key]
    word = 'removed'
  } else if (action === 'reviewed') {
    entry.state = 'reviewed'
    word = 'marked-reviewed'
  } else {
    if (entry.state === 'reviewed') return 'no-record'
    entry.state = 'reviewing'
    entry.lease_until = minutesFromNow(20)
    word = 'renewed'
  }
  const tmp = recordPath + '.tmp'
  writeFileSync(tmp, JSON.stringify(record, null, 2), 'utf8')
  renameSync(tmp, recordPath)
  return word
}

if (!acquire()) { console.log('locked'); process.exit(2) }
let word
try {
  word = update()
} finally {
  // process.exit would skip this, so nothing above exits while the lock is held.
  try { unlinkSync(lockPath) } catch {}
}
console.log(word)
