#!/usr/bin/env python3
# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
#  Script used to create a top_common_pc_definition_pkg.sv file.
# ==============================================================================================

import os       # OS functions
import sys      # manage errors
import argparse # parse input argument
import pathlib  # Get current file path
import jinja2
import math

TEMPLATE_NAME = "top_common_pc_definition_pkg.sv.j2"

#=====================================================
# Main
#=====================================================
if __name__ == '__main__':

#=====================================================
# Parse input arguments
#=====================================================
    parser = argparse.ArgumentParser(description = "Create a module directory structure.")
    parser.add_argument('-pem_pc',dest='pem_pc',    type=int, help="Number of PC for PEM", default=1)
    parser.add_argument('-glwe_pc',dest='glwe_pc',  type=int, help="Number of PC for GLWE", default=1)
    parser.add_argument('-bsk_pc',dest='bsk_pc',    type=int, help="Number of PC for BSK", default=1)
    parser.add_argument('-ksk_pc',dest='ksk_pc',    type=int, help="Number of PC for KSK", default=1)
    parser.add_argument('-o',  dest='outfile',      type=str, help="Output filename.", required=True)
    parser.add_argument('-f',  dest='force',        help="Overwrite if file already exists", action="store_true", default=False)

    args = parser.parse_args()

#=====================================================
# Create files
#=====================================================
    template_path   = os.path.join(pathlib.Path(__file__).parent.absolute(), "templates")
    template_loader = jinja2.FileSystemLoader(searchpath=template_path)
    template_env    = jinja2.Environment(loader=template_loader)

    config = {"pem_pc"  : args.pem_pc,
              "glwe_pc" : args.glwe_pc,
              "bsk_pc"  : args.bsk_pc,
              "ksk_pc"  : args.ksk_pc}

    template = template_env.get_template(TEMPLATE_NAME)
    file_path = args.outfile
    if (os.path.exists(file_path) and not(args.force)):
        sys.exit("ERROR> File {:s} already exists".format(file_path))
    else:
        if (os.path.exists(file_path)):
            print("INFO> File {:s} already exists. Overwrite it.".format(file_path))
        with open(file_path, 'w') as fp:
            fp.write(template.render(config))

