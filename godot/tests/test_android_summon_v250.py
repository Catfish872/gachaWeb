"""Offline contracts for real-ADB summon evidence; no emulator claim."""
import copy
import importlib.util
from pathlib import Path
import unittest
import tempfile
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('smoke',ROOT/'tools/android/smoke_test.py')
smoke=importlib.util.module_from_spec(spec);spec.loader.exec_module(smoke)
class SummonEvidence(unittest.TestCase):
    def fixture(self):
        return {'application_paused':False,'summon':{'active':True,'diamonds':1440,'total_pulls':1,'results':[{'charId':'ember'}],'owned_ids':['ember'],'transaction_digest':'exact','stage':'result','index':0,'sequence_time':3.8,'ready_frames':2,'rarity':3,'history':[{'stage':s} for s in ['opening','constellation','seal','unseal','portrait','result']]}}
    def test_exact_commit(self):
        after=self.fixture();before=copy.deepcopy(after);before['summon'].update(diamonds=1600,total_pulls=0)
        smoke.verify_summon_commit(before,after,1)
        for field,value in [('diamonds',1280),('total_pulls',2),('results',[]),('owned_ids',[])]:
            bad=copy.deepcopy(after);bad['summon'][field]=value
            with self.subTest(field=field),self.assertRaises(AssertionError):smoke.verify_summon_commit(before,bad,1)
    def test_pause_rejects_clock_stage_and_transaction_drift(self):
        paused=self.fixture();paused['application_paused']=True;resumed=self.fixture()
        smoke.verify_summon_pause(paused,resumed)
        for field,value in [('sequence_time',4),('stage','summary'),('index',1),('transaction_digest','rerolled'),('results',[{'charId':'ayla'}]),('active',False)]:
            bad=copy.deepcopy(resumed);bad['summon'][field]=value
            with self.subTest(field=field),self.assertRaises(AssertionError):smoke.verify_summon_pause(paused,bad)
    def test_full_visible_history_not_static_result_only(self):
        q=self.fixture();smoke.verify_summon_history(q)
        for field,value in [('history',[{'stage':'result'}]),('ready_frames',0),('sequence_time',.2)]:
            bad=copy.deepcopy(q);bad['summon'][field]=value
            with self.subTest(field=field),self.assertRaises(AssertionError):smoke.verify_summon_history(bad)
    def test_legendary_requires_own_phase(self):
        q=self.fixture();q['summon']['rarity']=5
        with self.assertRaises(AssertionError):smoke.verify_summon_history(q)
        q['summon']['history'].insert(4,{'stage':'legendary'});smoke.verify_summon_history(q)
    def test_real_driver_uses_pause_skip_and_virtual_purchase_inputs(self):
        before=self.fixture();before['summon'].update(active=False,diamonds=1600,total_pulls=0)
        one=self.fixture();one.update(screen='summon',seq=10,overlay=1)
        one['summon']['stage']='constellation'
        paused=copy.deepcopy(one);paused.update(application_paused=True,seq=11)
        resumed=copy.deepcopy(one);resumed['seq']=12
        result=self.fixture();result.update(screen='summon',seq=13,overlay=1)
        summary=copy.deepcopy(result);summary['summon'].update(stage='summary',visible_cards=1)
        accepted=copy.deepcopy(summary);accepted.update(overlay=0);accepted['summon']['active']=False
        topups=[]
        for diamonds in [1500,1560,1620]:
            q=copy.deepcopy(accepted);q['screen']='shop';q['summon']['diamonds']=diamonds;topups.append(q)
        ten=copy.deepcopy(result);ten['summon'].update(diamonds=20,total_pulls=11,results=[{'charId':'ember'}]*10,transaction_digest='ten',stage='opening',sequence_time=.8)
        ten_summary=copy.deepcopy(ten);ten_summary['summon'].update(stage='summary',visible_cards=10)
        ten_done=copy.deepcopy(ten_summary);ten_done.update(overlay=0);ten_done['summon']['active']=False
        home=copy.deepcopy(ten_done);home['screen']='home'
        states=[one,result,summary,accepted,*topups,ten,ten_summary,ten_done]
        def waiting(predicate,description,timeout=30):
            q=states.pop(0)
            self.assertTrue(predicate(q),description)
            return q
        with tempfile.TemporaryDirectory() as folder, patch.object(smoke,'visit',side_effect=[before,accepted,topups[-1],home]),patch.object(smoke,'wait_for',side_effect=waiting),patch.object(smoke,'wait_probe_event',side_effect=[paused,resumed]),patch.object(smoke,'tap') as tap,patch.object(smoke,'tap_page') as buy,patch.object(smoke,'adb') as adb,patch.object(smoke,'wait_for_completed_background'),patch.object(smoke,'screenshot'),patch.object(smoke,'back'):
            actual=smoke.summon_input_flow(before,'game/activity',Path(folder))
            self.assertEqual(actual['screen'],'home')
            self.assertEqual([call.args[1] for call in tap.call_args_list],['SummonPull_1','SummonSkip','SummonAccept','SummonPull_10','SummonSkip','SummonAccept'])
            self.assertEqual([call.args[1] for call in buy.call_args_list],['ShopPurchase_recharge_traveler']*3)
            adb.assert_any_call('shell','input','keyevent','KEYCODE_HOME')
            self.assertTrue((Path(folder)/'summon-single-lifecycle.json').exists())
            self.assertFalse(states)
    def test_local_page_scroll_does_not_require_outer_scroll(self):
        start={'buttons':[{'name':'GrowthSelect_zeph','rect':[20,800,100,60],'clip':[0,100,400,400],'scroll_owner':'local'}], 'scroll_max':0,'page_scrolls':[{'id':'local','rect':[0,100,400,400],'clip':[0,100,400,400],'max':800,'value':0}]}
        end=copy.deepcopy(start);end['buttons'][0]['rect'][1]=200;end['page_scrolls'][0]['value']=600
        def waiting(predicate,description):self.assertTrue(predicate(end));return end
        with patch.object(smoke,'adb') as adb,patch.object(smoke,'wait_for',side_effect=waiting):
            self.assertEqual(smoke.reveal_page_target(start,'GrowthSelect_zeph'),end)
            self.assertEqual(adb.call_args.args[:3],('shell','input','swipe'))
    def test_auto_return_requires_no_remaining_and_preserves_exact_assets(self):
        before={'extraction':{'phase':'room','room_id':'r','gold':100,'bag_ids':['u'],'containers':[{'id':'box','items':[]}],'interaction':{'canAutoReturn':True}}}
        after=copy.deepcopy(before);after.update(overlay=0,canvases={'map':{}});after['extraction']['phase']='route'
        smoke.verify_completed_container_close(before,after)
        for key,value in [('phase','room'),('room_id','other'),('bag_ids',[]),('containers',[]),('gold',99)]:
            bad=copy.deepcopy(after);bad['extraction'][key]=value
            with self.subTest(key=key),self.assertRaises(AssertionError):smoke.verify_completed_container_close(before,bad)
        before['extraction']['interaction']['canAutoReturn']=False
        with self.assertRaises(AssertionError):smoke.verify_completed_container_close(before,after)
        after['extraction']['phase']='room';smoke.verify_completed_container_close(before,after)
    def test_return_map_restores_retained_auxiliary_tab_by_real_input(self):
        for phase in ['room','route']:
            for tab in ['bag','build']:
                start={'seq':10,'buttons':[{'name':'ExtractionTab_expedition'},{'name':'ExtractionTab_'+tab}], 'extraction':{'phase':phase},'canvases':{}}
                explored=copy.deepcopy(start);explored['seq']=11
                if phase=='room':explored['buttons'].append({'name':'ExtractionAdvance'})
                else:explored['canvases']['map']={}
                final=copy.deepcopy(explored);final['seq']=12;final['extraction']['phase']='route';final['canvases']['map']={}
                expected=[explored,final] if phase=='room' else [explored]
                def waiting(predicate,description):
                    q=expected.pop(0)
                    stale=copy.deepcopy(q);stale['seq']=10
                    self.assertFalse(predicate(stale),'must reject pre-click/stale observation')
                    self.assertTrue(predicate(q),description)
                    return q
                with self.subTest(phase=phase,tab=tab),patch.object(smoke,'tap_page') as tap,patch.object(smoke,'wait_for',side_effect=waiting):
                    actual=smoke.return_extraction_map(start)
                    self.assertIn('map',actual['canvases'])
                    self.assertEqual([c.args[1] for c in tap.call_args_list],['ExtractionTab_expedition']+(['ExtractionAdvance'] if phase=='room' else []))
                    self.assertFalse(expected)
    def test_return_map_visible_map_needs_no_extra_click(self):
        state={'seq':10,'buttons':[], 'extraction':{'phase':'route'},'canvases':{'map':{}}}
        with patch.object(smoke,'tap_page') as tap:
            self.assertIs(smoke.return_extraction_map(state),state);tap.assert_not_called()
    def test_relic_scope_runs_only_real_remaining_flow_and_reports_reuse(self):
        with tempfile.TemporaryDirectory() as folder,patch.object(smoke,'relic_input_flow',return_value={'screen':'home'}) as relic,patch.object(smoke,'check_background_resume') as resume,patch.object(smoke,'adb',return_value='alive'),patch.object(smoke,'extraction_flow') as extraction,patch.object(smoke,'summon_input_flow') as summon:
            smoke.run_relic_scope({'screen':'home'},'component',Path(folder))
            relic.assert_called_once();resume.assert_called_once();extraction.assert_not_called();summon.assert_not_called()
            import json
            report=json.loads((Path(folder)/'result.json').read_text())
            self.assertEqual(report['scope'],'relic-v250');self.assertEqual(report['reused_evidence']['run'],41320178121)
            self.assertTrue(report['passed']);self.assertIn('summon single/ten/animation pause',report['not_rerun'])
    def test_explicit_relic_scope_branches_after_real_install_startup(self):
        state={'screen':'home','overlay':0,'window':[1280,720],'renderer':{'method':'mobile','driver':'vulkan','adapter':'test-observation'},'android_bridge':{}}
        with tempfile.TemporaryDirectory() as folder,patch.dict(smoke.os.environ,{'ANDROID_SMOKE_SCOPE':'relic-v250'}),patch.object(smoke,'adb',return_value='package/activity') as adb,patch.object(smoke,'settle_android_configuration'),patch.object(smoke,'wait_for',return_value=state),patch.object(smoke,'validate_android_bridge',return_value={}),patch.object(smoke,'geometry'),patch.object(smoke,'dismiss_fullscreen_education'),patch.object(smoke,'screenshot'),patch.object(smoke,'run_relic_scope') as remainder,patch.object(smoke,'tap') as tap,patch.object(smoke,'extraction_flow') as extraction,patch.object(smoke,'summon_input_flow') as summon:
            smoke.run(Path('real.apk'),Path(folder))
            adb.assert_any_call('install','-r','real.apk');adb.assert_any_call('shell','pm','clear',smoke.PACKAGE)
            remainder.assert_called_once_with(state,'package/activity',Path(folder))
            tap.assert_not_called();extraction.assert_not_called();summon.assert_not_called()
if __name__=='__main__':unittest.main()
