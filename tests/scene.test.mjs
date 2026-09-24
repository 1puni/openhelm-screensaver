import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {readSaverScene} from '../tools/screensaver-scene.mjs';
import {computeLineOfSightAlpha} from '../tools/screensaver-capture-page.mjs';

test('preview timing, coordinate and range match its retained NOAA record', async () => {
  const scene=await readSaverScene('screensaver/Scenes/alcatraz-noaa-preview.json');
  const receipt=JSON.parse(await readFile('screensaver/Provenance/noaa/build-receipt.json','utf8'));
  const record=receipt.lightRecord;
  assert.deepEqual(scene.light.coordinate,record.geometry.coordinates);
  assert.equal(scene.light.periodSeconds,record.properties.SIGPER);
  assert.equal(record.properties.SIGSEQ,'00.5+(04.5)');
  assert.deepEqual(scene.light.pulses,[{start:0,end:0.5}]);
  assert.equal(scene.light.sectors[0].rangeNauticalMiles,record.properties.VALNMR);
});
test('charted land and water behind an island remain outside the moving beam', () => {
  const width=40,height=30,land=new Uint8Array(width*height);
  for(let y=9;y<=21;y++)for(let x=20;x<=22;x++)land[y*width+x]=1;
  const alpha=computeLineOfSightAlpha({land,width,height,anchorX:5,anchorY:15,clearancePixels:1});
  assert.equal(alpha[15*width+12],255);
  assert.equal(alpha[15*width+21],0);
  assert.equal(alpha[15*width+32],0);
  assert.equal(alpha[2*width+12],255);
});
