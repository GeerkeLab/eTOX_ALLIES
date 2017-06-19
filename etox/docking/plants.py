# -*- coding: utf-8 -*-

"""
This file contains all the PLANTS methods for etoxsys.
"""

import os
import textwrap
import shutil
import glob

from eTOX_ALLIES.etox.core.molHandler import mols2single
from .. import settings

PLANTS = settings.get('PLANTS')
CMD = [PLANTS, '--mode' ,'screen' ,'plants.conf']
INPUTFMT='mol2'

def prepareDocking(liglist,proteinf,settings):
    '''This function sets up docking with PLANTS so that CMD can be executed by the script.
       Requires the protein for docking as separate input. The other arguments should be named and are passed to Conf().'''
    outFile=mols2single(liglist,output='molecule',format='mol2')
    settings['customset']['ligand']=os.path.basename(outFile)
    inputf = open('plants.conf','w')
    conf = Conf(**settings)
    inputf.write(conf.mode('custom'))
    inputf.close()
    shutil.copy(proteinf,  '.')
    return


def solveDocking():
    '''This function handles the docking solutions generated by the script.
       It should return a list of the filenames that will be analyzed, filtered and clustered'''
    solutions=glob.glob('*_entry_*.mol2')    #all plants solutions are retrieved in a list
    return solutions


class Conf:
    '''Defines a PLANTS configuration file
         Its possible to initialize with a custom dictionary, 
         or modify elements later with setCustom()'''
    def __init__(self,customset=None):
        '''Sets up a plants configuration file as a string. Sets up dicts with presets'''
        self.text=textwrap.dedent('''
        ### Scoring function and search settings ###
        scoring_function {0[scoring_function]}
        search_speed         {0[search_speed]}
        
        ### Input file specification
        protein_file    {0[proteinDock]} 
        ligand_file     {0[ligand]}
     
        ### Output settings
        output_dir {0[output_dir]}
        write_multi_mol2 {0[write_multi_mol2]}
        ### Ligand settings
        flip_amide_bonds     {0[flip_amide_bonds]}
        flip_planar_n            {0[flip_planar_n]}
 
        ### Binding site definition
        bindingsite_center {0[pocket][0]} {0[pocket][1]} {0[pocket][2]}
        bindingsite_radius {0[radius]}
        
        ### cluster algorithm
        cluster_structures {0[cluster_structures]}
        cluster_rmsd             {0[cluster_rmsd]}
        
        ### Writer
        write_ranking_links {0[write_ranking_links]}
        write_protein_bindingsite {0[write_protein_bindingsite]}
        write_protein_conformations {0[write_protein_conformations]}
        write_merged_protein {0[write_merged_protein]}
        ####''').strip('\n')
        
        #Set default dictionary
        self.defaults=dict(scoring_function='chemplp',
            search_speed='speed1',
            proteinDock='protein.mol2',
            ligand='ligand.mol2',
            output_dir='.',
            write_multi_mol2=0,
            flip_amide_bonds=1,
            flip_planar_n=1,
            pocket=[0.0,0.0,0.0],
            radius=12,
            cluster_structures=50,
            cluster_rmsd=1.0,
            write_ranking_links=0,
            write_protein_bindingsite=0,
            write_protein_conformations=0,
            write_merged_protein=0)
        #custom is a copy of the defaults unless modified by user
        self.customset=self.defaults.copy()
        if customset is not None:
            self.customset.update(customset)
        #The quick and dirty settings
        self.quick=dict(scoring_function='chemplp',
            search_speed='speed4',
            proteinDock='protein.mol2',
            ligand='ligand.mol2',
            output_dir='.',
            write_multi_mol2=0,
            flip_amide_bonds=0,
            flip_planar_n=1,
            pocket=[0.0,0.0,0.0],
            radius=12,
            cluster_structures=50,
            cluster_rmsd=1.0,
            write_ranking_links=0,
            write_protein_bindingsite=0,
            write_protein_conformations=0,
            write_merged_protein=0)
        #Slow but precise settings    
        self.slow=dict(scoring_function='chemplp',
            search_speed='speed1',
            proteinDock='protein.mol2',
            ligand='ligand.mol2',
            output_dir='.',
            write_multi_mol2=0,
            flip_amide_bonds=0,
            flip_planar_n=1,
            pocket=[0.0,0.0,0.0],
            radius=12,
            cluster_structures=150,
            cluster_rmsd=1.0,
            write_ranking_links=0,
            write_protein_bindingsite=0,
            write_protein_conformations=0,
            write_merged_protein=0)
            
        self.presets = {'default':    self.defaults,
                            'dirty' :        self.quick,
                            'precise'    : self.slow,
                            'custom'    :    self.customset,
                            }
         
         
    def setText(self,txt):
        '''Allows user to change the default configuration string'''
        self.text=str(txt)
    
    def getText(self):
        '''Allows user to retrieve current configuration string'''
        return self.text 
    
    def setCustom(self,**kwargs):
        '''User can set the individual values in the custom preset to whatever is desired
             use key= and value= to change one value.
             Its also possible to change the entire list to one predefined preset with preset='''
        if 'preset' in kwargs and len(kwargs) == 1:
            if kwargs['preset'] in self.presets:
                self.customset.update(self.presets.get(kwargs['preset']))
            else:
                raise Exception, 'Use preset=, or key= and val= as arguments!'
        elif 'key' in kwargs and 'val' in kwargs and len(kwargs) == 2:            
            self.customset[kwargs['key']]=kwargs['val']
        else:            
            raise Exception, 'Use preset=, or key= and val= as arguments!'
        
    def mode(self,preset):
        '''Returns formatted Gold configuration file with values set to preset requested.'''
        if preset in self.presets:
            return self.text.format(self.presets[preset])
        else:
            raise Exception, 'Unknown preset!'