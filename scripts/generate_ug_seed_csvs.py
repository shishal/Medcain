#!/usr/bin/env python3
"""LEGACY seed generator — do not use for the current CMS.

The live content pipeline is one lean Questions.csv plus admin seeds under
content/admin/ and supabase/migrations/20260915200000_*.sql. This script still
emits multi-tab CSVs for historical reference only.

Usage (from repo root):
  python3 scripts/generate_ug_seed_csvs.py
"""

from __future__ import annotations

import csv
import re
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TABS = ROOT / "content" / "google_sheet" / "tabs"

PHASES = [
    ("year1", "1st year", 1),
    ("year2", "2nd year", 2),
    ("year3", "3rd year", 3),
    ("year4", "Final year", 4),
]

# Historical generator list. The live catalog is subject_phase_defaults
# (see supabase/migrations/20261010130000_mbbs_subject_catalog.sql).
SUBJECTS = [
    ("Anatomy", 1, "year1"),
    ("Physiology", 2, "year1"),
    ("Biochemistry", 3, "year1"),
    ("Pathology", 4, "year2"),
    ("Microbiology", 5, "year2"),
    ("Pharmacology", 6, "year2"),
    ("Forensic Medicine", 7, "year2"),
    ("Community Medicine", 8, "year3"),
    ("Medicine", 9, "year4"),
    ("Surgery", 10, "year4"),
    ("Obstetrics & Gynaecology", 11, "year4"),
    ("Pediatrics", 12, "year4"),
    ("Ophthalmology", 13, "year3"),
    ("ENT", 14, "year3"),
    ("Orthopedics", 15, "year4"),
    ("Dermatology", 16, "year4"),
    ("Psychiatry", 17, "year4"),
    ("Anesthesia", 18, "year4"),
    ("Radiology", 19, "year4"),
]

PREFIX = {
    "Anatomy": "ANAT",
    "Physiology": "PHYS",
    "Biochemistry": "BIOC",
    "Pathology": "PATH",
    "Microbiology": "MICR",
    "Pharmacology": "PHAR",
    "Forensic Medicine": "FMT",
    "Community Medicine": "PSM",
    "Medicine": "MED",
    "Surgery": "SUR",
    "Obstetrics & Gynaecology": "OBG",
    "Pediatrics": "PED",
    "Ophthalmology": "OPH",
    "ENT": "ENT",
    "Orthopedics": "ORT",
    "Dermatology": "DER",
    "Psychiatry": "PSY",
    "Anesthesia": "ANE",
    "Radiology": "RAD",
}

SUBJECT_SLUG = {
    "Anatomy": "anatomy",
    "Physiology": "physiology",
    "Biochemistry": "biochemistry",
    "Pathology": "pathology",
    "Microbiology": "microbiology",
    "Pharmacology": "pharmacology",
    "Forensic Medicine": "forensic-medicine",
    "Community Medicine": "community-medicine",
    "Medicine": "medicine",
    "Surgery": "surgery",
    "Obstetrics & Gynaecology": "obstetrics-gynaecology",
    "Pediatrics": "pediatrics",
    "Ophthalmology": "ophthalmology",
    "ENT": "ent",
    "Orthopedics": "orthopedics",
    "Dermatology": "dermatology",
    "Psychiatry": "psychiatry",
    "Anesthesia": "anesthesia",
    "Radiology": "radiology",
}

# Existing Topics.csv plus a few high-yield gaps (thorax/abdomen/lower limb, etc.).
TOPICS = [
    ("Anatomy", "Upper Limb Anatomy", 1),
    ("Anatomy", "Head and Neck Anatomy", 2),
    ("Anatomy", "Neuroanatomy", 3),
    ("Anatomy", "Embryology", 4),
    ("Anatomy", "Thorax Anatomy", 5),
    ("Anatomy", "Abdomen Anatomy", 6),
    ("Anatomy", "Lower Limb Anatomy", 7),
    ("Physiology", "Cardiovascular Physiology", 1),
    ("Physiology", "Respiratory Physiology", 2),
    ("Physiology", "Renal Physiology", 3),
    ("Physiology", "Neurophysiology", 4),
    ("Physiology", "Endocrine Physiology", 5),
    ("Physiology", "Gastrointestinal Physiology", 6),
    ("Biochemistry", "Carbohydrate Metabolism", 1),
    ("Biochemistry", "Amino Acid Metabolism", 2),
    ("Biochemistry", "Molecular Biology", 3),
    ("Biochemistry", "Vitamins and Nutrition", 4),
    ("Biochemistry", "Lipid Metabolism", 5),
    ("Pathology", "General Pathology", 1),
    ("Pathology", "Hematopathology", 2),
    ("Pathology", "Systemic Pathology", 3),
    ("Pathology", "Neoplasia", 4),
    ("Microbiology", "Bacteriology", 1),
    ("Microbiology", "Virology", 2),
    ("Microbiology", "Parasitology", 3),
    ("Microbiology", "Immunology", 4),
    ("Pharmacology", "Autonomic Pharmacology", 1),
    ("Pharmacology", "Cardiovascular Pharmacology", 2),
    ("Pharmacology", "Antimicrobial Pharmacology", 3),
    ("Pharmacology", "CNS Pharmacology", 4),
    ("Forensic Medicine", "Forensic Thanatology", 1),
    ("Forensic Medicine", "Forensic Toxicology", 2),
    ("Forensic Medicine", "Medical Jurisprudence", 3),
    ("Community Medicine", "Epidemiology", 1),
    ("Community Medicine", "Biostatistics", 2),
    ("Community Medicine", "National Health Programs", 3),
    ("Community Medicine", "Immunization", 4),
    ("Medicine", "Cardiology", 1),
    ("Medicine", "Pulmonology", 2),
    ("Medicine", "Gastroenterology", 3),
    ("Medicine", "Endocrinology", 4),
    ("Medicine", "Neurology", 5),
    ("Medicine", "Nephrology", 6),
    ("Surgery", "General Surgery", 1),
    ("Surgery", "GI Surgery", 2),
    ("Surgery", "Urology", 3),
    ("Surgery", "Neurosurgery", 4),
    ("Surgery", "Breast and Endocrine Surgery", 5),
    ("Obstetrics & Gynaecology", "Obstetrics", 1),
    ("Obstetrics & Gynaecology", "Gynaecology", 2),
    ("Obstetrics & Gynaecology", "Labour and Delivery", 3),
    ("Pediatrics", "Neonatology", 1),
    ("Pediatrics", "Pediatric Infectious Disease", 2),
    ("Pediatrics", "Pediatric Growth and Development", 3),
    ("Ophthalmology", "Cornea and Conjunctiva", 1),
    ("Ophthalmology", "Glaucoma", 2),
    ("Ophthalmology", "Retina", 3),
    ("ENT", "Otology", 1),
    ("ENT", "Rhinology", 2),
    ("ENT", "Laryngology", 3),
    ("Orthopedics", "Fracture Management", 1),
    ("Orthopedics", "Bone and Joint Infection", 2),
    ("Orthopedics", "Spine Orthopedics", 3),
    ("Dermatology", "Papulosquamous Disorders", 1),
    ("Dermatology", "Cutaneous Infections", 2),
    ("Dermatology", "Bullous Disorders", 3),
    ("Psychiatry", "Mood Disorders", 1),
    ("Psychiatry", "Schizophrenia Spectrum", 2),
    ("Psychiatry", "Anxiety and Substance Use", 3),
    ("Anesthesia", "General Anesthesia", 1),
    ("Anesthesia", "Regional Anesthesia", 2),
    ("Anesthesia", "Airway Management", 3),
    ("Radiology", "Chest Radiology", 1),
    ("Radiology", "Abdominal Radiology", 2),
    ("Radiology", "Neuroradiology", 3),
]

TOPIC_SUBJECT = {name: subj for subj, name, _ in TOPICS}

UNIVERSITIES = [
    ("KUHS", "Kerala University of Health Sciences", "Kerala"),
    ("RGUHS", "Rajiv Gandhi University of Health Sciences", "Karnataka"),
    ("NTRUHS", "Dr. NTR University of Health Sciences", "Andhra Pradesh"),
    ("KNRUHS", "Kaloji Narayana Rao University of Health Sciences", "Telangana"),
    ("TNMGRMU", "Tamil Nadu Dr. M.G.R. Medical University", "Tamil Nadu"),
    ("WBUHS", "West Bengal University of Health Sciences", "West Bengal"),
    ("RUHS", "Rajasthan University of Health Sciences", "Rajasthan"),
    ("MUHS", "Maharashtra University of Health Sciences", "Maharashtra"),
]

# Starter colleges so onboarding is never empty for a listed university.
STARTER_COLLEGES = {
    "RGUHS": [
        "Bangalore Medical College and Research Institute",
        "Mysore Medical College and Research Institute",
    ],
    "NTRUHS": [
        "Andhra Medical College, Visakhapatnam",
        "Guntur Medical College",
    ],
    "KNRUHS": [
        "Osmania Medical College, Hyderabad",
        "Gandhi Medical College, Secunderabad",
    ],
    "TNMGRMU": [
        "Madras Medical College, Chennai",
        "Stanley Medical College, Chennai",
    ],
    "WBUHS": [
        "Medical College, Kolkata",
        "Nil Ratan Sircar Medical College, Kolkata",
    ],
    "RUHS": [
        "SMS Medical College, Jaipur",
        "Dr. SN Medical College, Jodhpur",
    ],
    "MUHS": [
        "Grant Medical College, Mumbai",
        "B.J. Government Medical College, Pune",
    ],
}

COLLEGES = [
    "Government Medical College, Thiruvananthapuram",
    "Government Medical College, Kozhikode",
    "Government Medical College, Kottayam",
    "Government Medical College, Thrissur",
    "Government Medical College, Kannur (Pariyaram)",
    "Government Medical College, Ernakulam",
    "Government Medical College, Kollam",
    "Government Medical College, Manjeri",
    "Government Medical College, Idukki",
    "Government Medical College, Konni",
    "Government Medical College, Palakkad",
    "Government Medical College, Wayanad",
    "Amrita School of Medicine, Kochi",
    "Jubilee Mission Medical College, Thrissur",
    "Malankara Orthodox Syrian Church Medical College, Kolenchery",
    "Pushpagiri Institute of Medical Sciences, Thiruvalla",
    "Travancore Medical College, Kollam",
    "Sree Gokulam Medical College, Venjaramoodu",
    "KMCT Medical College, Kozhikode",
    "MES Medical College, Perinthalmanna",
    "Malabar Medical College, Kozhikode",
    "Azeezia Institute of Medical Sciences, Kollam",
    "SUT Academy of Medical Sciences, Thiruvananthapuram",
    "Dr. Somervell Memorial CSI Medical College, Karakonam",
    "Believers Church Medical College, Thiruvalla",
    "Al Azhar Medical College, Thodupuzha",
    "P K Das Institute of Medical Sciences, Ottapalam",
    "Sree Narayana Institute of Medical Sciences, Ernakulam",
    "Mount Zion Medical College, Adoor",
    "Karuna Medical College, Palakkad",
]

TEXTBOOKS = [
    ("TB-BDCHAURASIA-VOL1-8", "Human Anatomy Volume 1 (Upper Limb and Thorax)", "BD Chaurasia", "8th"),
    ("TB-BDCHAURASIA-VOL2-8", "Human Anatomy Volume 2 (Lower Limb, Abdomen and Pelvis)", "BD Chaurasia", "8th"),
    ("TB-BDCHAURASIA-VOL3-8", "Human Anatomy Volume 3 (Head, Neck and Brain)", "BD Chaurasia", "8th"),
    ("TB-SNELL-9", "Clinical Anatomy by Regions", "Richard S. Snell", "9th"),
    ("TB-GUYTON-14", "Guyton and Hall Textbook of Medical Physiology", "Hall JE", "14th"),
    ("TB-GANONG-26", "Ganong's Review of Medical Physiology", "Barrett et al.", "26th"),
    ("TB-VASUDEVAN-9", "Textbook of Biochemistry for Medical Students", "DM Vasudevan", "9th"),
    ("TB-SATYANARAYANA-5", "Biochemistry", "Satyanarayana and Chakrapani", "5th"),
    ("TB-ROBBINS-10", "Robbins and Cotran Pathologic Basis of Disease", "Kumar, Abbas, Aster", "10th"),
    ("TB-HARSHMOHAN-8", "Textbook of Pathology", "Harsh Mohan", "8th"),
    ("TB-PANIKER-8", "Ananthanarayan and Paniker's Textbook of Microbiology", "Reba Kanungo", "8th"),
    ("TB-KDTRPATHI-8", "Essentials of Medical Pharmacology", "KD Tripathi", "8th"),
    ("TB-REDDY-34", "The Essentials of Forensic Medicine and Toxicology", "KS Narayan Reddy", "34th"),
    ("TB-PARK-26", "Park's Textbook of Preventive and Social Medicine", "K Park", "26th"),
    ("TB-HARRISON-21", "Harrison's Principles of Internal Medicine", "Jameson et al.", "21st"),
    ("TB-API-12", "API Textbook of Medicine", "Yash Pal Munjal", "12th"),
    ("TB-BAILEY-28", "Bailey & Love's Short Practice of Surgery", "Williams, O'Connell, McCaskie", "28th"),
    ("TB-SRB-6", "SRB's Manual of Surgery", "Sriram Bhat M", "6th"),
    ("TB-DUTTA-9", "DC Dutta's Textbook of Obstetrics", "Hiralal Konar", "9th"),
    ("TB-SHAW-17", "Shaw's Textbook of Gynaecology", "Padubidri and Daftary", "17th"),
    ("TB-GHAI-9", "Ghai Essential Pediatrics", "Vinod K Paul, Arvind Bagga", "9th"),
    ("TB-KHURANA-7", "Comprehensive Ophthalmology", "AK Khurana", "7th"),
    ("TB-DHINGRA-7", "Diseases of Ear, Nose and Throat", "PL Dhingra", "7th"),
    ("TB-DHINGRA-8", "Diseases of Ear, Nose and Throat", "PL Dhingra", "8th"),
    ("TB-MAHESHWARI-6", "Essential Orthopaedics", "Maheshwari and Mhaskar", "6th"),
    ("TB-NEENAKHANNA-5", "Illustrated Synopsis of Dermatology and STDs", "Neena Khanna", "5th"),
    ("TB-AHUJA-8", "A Short Textbook of Psychiatry", "Niraj Ahuja", "8th"),
    ("TB-MORGAN-6", "Morgan and Mikhail's Clinical Anesthesiology", "Butterworth et al.", "6th"),
    ("TB-SUTTON-7", "Textbook of Radiology and Imaging", "David Sutton", "7th"),
]

TOPIC_TEXTBOOK = {
    "Upper Limb Anatomy": ("TB-BDCHAURASIA-VOL1-8", 48),
    "Head and Neck Anatomy": ("TB-BDCHAURASIA-VOL3-8", 210),
    "Neuroanatomy": ("TB-BDCHAURASIA-VOL3-8", 340),
    "Embryology": ("TB-SNELL-9", 52),
    "Thorax Anatomy": ("TB-BDCHAURASIA-VOL1-8", 180),
    "Abdomen Anatomy": ("TB-BDCHAURASIA-VOL2-8", 120),
    "Lower Limb Anatomy": ("TB-BDCHAURASIA-VOL2-8", 28),
    "Cardiovascular Physiology": ("TB-GUYTON-14", 109),
    "Respiratory Physiology": ("TB-GUYTON-14", 497),
    "Renal Physiology": ("TB-GUYTON-14", 343),
    "Neurophysiology": ("TB-GANONG-26", 85),
    "Endocrine Physiology": ("TB-GUYTON-14", 921),
    "Gastrointestinal Physiology": ("TB-GUYTON-14", 797),
    "Carbohydrate Metabolism": ("TB-VASUDEVAN-9", 112),
    "Amino Acid Metabolism": ("TB-VASUDEVAN-9", 198),
    "Molecular Biology": ("TB-SATYANARAYANA-5", 412),
    "Vitamins and Nutrition": ("TB-VASUDEVAN-9", 386),
    "Lipid Metabolism": ("TB-VASUDEVAN-9", 156),
    "General Pathology": ("TB-ROBBINS-10", 31),
    "Hematopathology": ("TB-HARSHMOHAN-8", 280),
    "Systemic Pathology": ("TB-ROBBINS-10", 523),
    "Neoplasia": ("TB-ROBBINS-10", 267),
    "Bacteriology": ("TB-PANIKER-8", 188),
    "Virology": ("TB-PANIKER-8", 440),
    "Parasitology": ("TB-PANIKER-8", 612),
    "Immunology": ("TB-PANIKER-8", 78),
    "Autonomic Pharmacology": ("TB-KDTRPATHI-8", 92),
    "Cardiovascular Pharmacology": ("TB-KDTRPATHI-8", 521),
    "Antimicrobial Pharmacology": ("TB-KDTRPATHI-8", 688),
    "CNS Pharmacology": ("TB-KDTRPATHI-8", 401),
    "Forensic Thanatology": ("TB-REDDY-34", 148),
    "Forensic Toxicology": ("TB-REDDY-34", 498),
    "Medical Jurisprudence": ("TB-REDDY-34", 42),
    "Epidemiology": ("TB-PARK-26", 58),
    "Biostatistics": ("TB-PARK-26", 786),
    "National Health Programs": ("TB-PARK-26", 412),
    "Immunization": ("TB-PARK-26", 118),
    "Cardiology": ("TB-HARRISON-21", 1760),
    "Pulmonology": ("TB-API-12", 890),
    "Gastroenterology": ("TB-HARRISON-21", 2234),
    "Endocrinology": ("TB-HARRISON-21", 2654),
    "Neurology": ("TB-HARRISON-21", 3050),
    "Nephrology": ("TB-API-12", 712),
    "General Surgery": ("TB-BAILEY-28", 48),
    "GI Surgery": ("TB-SRB-6", 612),
    "Urology": ("TB-BAILEY-28", 1398),
    "Neurosurgery": ("TB-BAILEY-28", 612),
    "Breast and Endocrine Surgery": ("TB-SRB-6", 428),
    "Obstetrics": ("TB-DUTTA-9", 112),
    "Gynaecology": ("TB-SHAW-17", 88),
    "Labour and Delivery": ("TB-DUTTA-9", 128),
    "Neonatology": ("TB-GHAI-9", 142),
    "Pediatric Infectious Disease": ("TB-GHAI-9", 228),
    "Pediatric Growth and Development": ("TB-GHAI-9", 12),
    "Cornea and Conjunctiva": ("TB-KHURANA-7", 88),
    "Glaucoma": ("TB-KHURANA-7", 226),
    "Retina": ("TB-KHURANA-7", 278),
    "Otology": ("TB-DHINGRA-7", 48),
    "Rhinology": ("TB-DHINGRA-7", 168),
    "Laryngology": ("TB-DHINGRA-7", 288),
    "Fracture Management": ("TB-MAHESHWARI-6", 82),
    "Bone and Joint Infection": ("TB-MAHESHWARI-6", 178),
    "Spine Orthopedics": ("TB-MAHESHWARI-6", 248),
    "Papulosquamous Disorders": ("TB-NEENAKHANNA-5", 42),
    "Cutaneous Infections": ("TB-NEENAKHANNA-5", 88),
    "Bullous Disorders": ("TB-NEENAKHANNA-5", 126),
    "Mood Disorders": ("TB-AHUJA-8", 78),
    "Schizophrenia Spectrum": ("TB-AHUJA-8", 52),
    "Anxiety and Substance Use": ("TB-AHUJA-8", 112),
    "General Anesthesia": ("TB-MORGAN-6", 148),
    "Regional Anesthesia": ("TB-MORGAN-6", 918),
    "Airway Management": ("TB-MORGAN-6", 308),
    "Chest Radiology": ("TB-SUTTON-7", 48),
    "Abdominal Radiology": ("TB-SUTTON-7", 612),
    "Neuroradiology": ("TB-SUTTON-7", 1488),
}

# Stable IDs already in the live sheet — never rename these.
LOCKED_LESSON_IDS = {
    ("Upper Limb Anatomy", "Brachial plexus"): "L-ANAT-UPPER-BRACHIAL",
    ("Upper Limb Anatomy", "Humerus fractures"): "L-ANAT-UPPER-HUMERUS",
    ("Head and Neck Anatomy", "Larynx"): "L-ANAT-HEAD-LARYNX",
}
LOCKED_LESSON_PLANS = {
    "L-ANAT-UPPER-BRACHIAL": "free",
    "L-ANAT-UPPER-HUMERUS": "free",
    "L-ANAT-HEAD-LARYNX": "pro",
}

LOCKED_PYQ_ROWS = [
    {
        "external_id": "Q-ANAT-PYQ-001",
        "topic_name": "Upper Limb Anatomy",
        "question_text": "Describe the formation of the brachial plexus. Add a note on Erb palsy.",
        "option_a": "",
        "option_b": "",
        "option_c": "",
        "option_d": "",
        "correct_option": "",
        "explanation_text": "",
        "explanation_video_url": "",
        "image_url": "",
        "difficulty": "should",
        "source": "KUHS PYQ",
        "required_plan": "free",
        "is_active": "TRUE",
        "kind": "pyq_theory",
        "lesson_external_id": "L-ANAT-UPPER-BRACHIAL",
        "marks": "10",
        "sample_answer_text": (
            "The brachial plexus is formed by the ventral rami of spinal nerves C5, C6, C7, C8 and T1. "
            "These roots emerge between scalenus anterior and scalenus medius in the posterior triangle of the neck. "
            "Roots unite to form three trunks: upper (C5–C6), middle (C7) and lower (C8–T1). "
            "Each trunk divides into anterior and posterior divisions behind the clavicle. "
            "Divisions regroup around the axillary artery as three cords named by position: lateral, medial and posterior.\n\n"
            "Branches to remember in an exam answer: dorsal scapular and long thoracic from roots; "
            "suprascapular and nerve to subclavius from the upper trunk; lateral pectoral and musculocutaneous "
            "plus the lateral root of median from the lateral cord; medial pectoral, medial cutaneous nerves of arm "
            "and forearm, ulnar and the medial root of median from the medial cord; upper and lower subscapular, "
            "thoracodorsal, axillary and radial from the posterior cord.\n\n"
            "Erb palsy follows injury at Erb's point (C5–C6), typically birth traction or a fall on the shoulder. "
            "The arm hangs adducted and internally rotated with the elbow extended, forearm pronated and wrist flexed — "
            "waiter's tip. Loss reflects suprascapular, axillary and musculocutaneous paralysis. "
            "Klumpke palsy (C8–T1) is a useful contrast: intrinsic hand wasting and a possible Horner syndrome "
            "if T1 white rami are involved. Close with prefixed (C4) or postfixed (T2) variants if marks remain."
        ),
    },
    {
        "external_id": "Q-ANAT-PYQ-002",
        "topic_name": "Upper Limb Anatomy",
        "question_text": "A fracture of the surgical neck of the humerus. Enumerate structures at risk.",
        "option_a": "",
        "option_b": "",
        "option_c": "",
        "option_d": "",
        "correct_option": "",
        "explanation_text": "",
        "explanation_video_url": "",
        "image_url": "",
        "difficulty": "could",
        "source": "KUHS PYQ",
        "required_plan": "free",
        "is_active": "TRUE",
        "kind": "pyq_theory",
        "lesson_external_id": "L-ANAT-UPPER-HUMERUS",
        "marks": "5",
        "sample_answer_text": "",
    },
]

LOCKED_PYQS = {row["lesson_external_id"]: row["external_id"] for row in LOCKED_PYQ_ROWS}
# First lesson is always free; second may be pro/elite (see plan_for).
LESSON_NAMES: dict[str, list[tuple[str, str]]] = {
    "Upper Limb Anatomy": [
        ("Brachial plexus", "Brachial_plexus"),
        ("Humerus fractures", "Humerus_fracture"),
    ],
    "Head and Neck Anatomy": [
        ("Larynx", "Larynx"),
        ("Thyroid gland and triangles of the neck", "Thyroid"),
    ],
    "Neuroanatomy": [
        ("Visual pathway", "Visual_pathway"),
        ("Circle of Willis and cranial nerve nuclei", "Circle_of_Willis"),
    ],
    "Embryology": [
        ("Gastrulation and notochord", "Gastrulation"),
        ("Pharyngeal arches and fetal circulation", "Pharyngeal_arch"),
    ],
    "Thorax Anatomy": [
        ("Heart and coronary arteries", "Coronary_circulation"),
        ("Bronchopulmonary segments and mediastinum", "Bronchopulmonary_segment"),
    ],
    "Abdomen Anatomy": [
        ("Inguinal canal and hernia", "Inguinal_canal"),
        ("Portal vein and extrahepatic biliary tree", "Portal_vein"),
    ],
    "Lower Limb Anatomy": [
        ("Femoral triangle and adductor canal", "Femoral_triangle"),
        ("Sciatic nerve and gluteal region", "Sciatic_nerve"),
    ],
    "Cardiovascular Physiology": [
        ("Cardiac cycle and heart sounds", "Cardiac_cycle"),
        ("Jugular venous pulse and ECG basics", "Jugular_venous_pressure"),
    ],
    "Respiratory Physiology": [
        ("Lung volumes and spirometry", "Spirometry"),
        ("Oxygen transport and hypoxia", "Hypoxia"),
    ],
    "Renal Physiology": [
        ("GFR and clearance", "Renal_function"),
        ("Countercurrent mechanism and ADH", "Countercurrent_multiplier_system"),
    ],
    "Neurophysiology": [
        ("Resting membrane potential and action potential", "Action_potential"),
        ("Synaptic transmission and neuromuscular junction", "Neuromuscular_junction"),
    ],
    "Endocrine Physiology": [
        ("Hypothalamo-pituitary axis", "Hypothalamic–pituitary–adrenal_axis"),
        ("Thyroid hormone synthesis and calcium hormones", "Thyroid_hormone"),
    ],
    "Gastrointestinal Physiology": [
        ("Gastric secretion and motility", "Gastric_acid"),
        ("Bile, pancreas and small-bowel absorption", "Bile"),
    ],
    "Carbohydrate Metabolism": [
        ("Glycolysis and gluconeogenesis", "Glycolysis"),
        ("Glycogen storage diseases and PPP", "Glycogen_storage_disease"),
    ],
    "Amino Acid Metabolism": [
        ("Urea cycle and hyperammonemia", "Urea_cycle"),
        ("Phenylalanine, tyrosine and branched-chain amino acids", "Phenylketonuria"),
    ],
    "Molecular Biology": [
        ("DNA replication and repair", "DNA_replication"),
        ("Transcription, translation and blotting", "Southern_blot"),
    ],
    "Vitamins and Nutrition": [
        ("Water-soluble vitamins", "Vitamin"),
        ("Fat-soluble vitamins and PEM", "Vitamin_A_deficiency"),
    ],
    "Lipid Metabolism": [
        ("Beta-oxidation and ketone bodies", "Beta_oxidation"),
        ("Cholesterol synthesis and lipoproteins", "Lipoprotein"),
    ],
    "General Pathology": [
        ("Cell injury, necrosis and apoptosis", "Necrosis"),
        ("Inflammation, healing and hemodynamic disorders", "Inflammation"),
    ],
    "Hematopathology": [
        ("Anemias and megaloblastic change", "Megaloblastic_anemia"),
        ("Leukemias and lymphomas", "Leukemia"),
    ],
    "Systemic Pathology": [
        ("Cardiovascular and renal pathology", "Rheumatic_fever"),
        ("Hepatic and pulmonary pathology", "Cirrhosis"),
    ],
    "Neoplasia": [
        ("Carcinogenesis and tumour markers", "Carcinogenesis"),
        ("Common cancers and paraneoplastic syndromes", "Paraneoplastic_syndrome"),
    ],
    "Bacteriology": [
        ("Gram-positive pathogens and mycobacteria", "Mycobacterium_tuberculosis"),
        ("Gram-negative and anaerobic bacteria", "Vibrio_cholerae"),
    ],
    "Virology": [
        ("Hepatitis viruses and HIV", "Hepatitis_B"),
        ("Herpesviruses, rabies and respiratory viruses", "Rabies"),
    ],
    "Parasitology": [
        ("Malaria and leishmaniasis", "Malaria"),
        ("Intestinal helminths and hydatid disease", "Echinococcosis"),
    ],
    "Immunology": [
        ("Hypersensitivity and antibodies", "Hypersensitivity"),
        ("Primary immunodeficiencies and transplant", "DiGeorge_syndrome"),
    ],
    "Autonomic Pharmacology": [
        ("Cholinergic and anticholinergic drugs", "Atropine"),
        ("Adrenergic agonists, blockers and NMJ drugs", "Neuromuscular-blocking_drug"),
    ],
    "Cardiovascular Pharmacology": [
        ("Antihypertensives and heart-failure drugs", "ACE_inhibitor"),
        ("Antiarrhythmics and anticoagulants", "Adenosine"),
    ],
    "Antimicrobial Pharmacology": [
        ("Beta-lactams, vancomycin and anti-TB drugs", "Isoniazid"),
        ("Antimalarials, antifungals and stewardship", "Artemisinin"),
    ],
    "CNS Pharmacology": [
        ("Antiepileptics and benzodiazepines", "Ethosuximide"),
        ("Antidepressants, lithium and antipsychotics", "Lithium_(medication)"),
    ],
    "Forensic Thanatology": [
        ("Early signs of death and rigor mortis", "Rigor_mortis"),
        ("Postmortem staining, cooling and injuries", "Livor_mortis"),
    ],
    "Forensic Toxicology": [
        ("Corrosives, pesticides and plant poisons", "Organophosphate_poisoning"),
        ("Asphyxiants, metals and alcohol", "Carbon_monoxide_poisoning"),
    ],
    "Medical Jurisprudence": [
        ("Consent, negligence and inquest", "Informed_consent"),
        ("Injury, dying declaration and IPC sections", "Dying_declaration"),
    ],
    "Epidemiology": [
        ("Measures of disease frequency and study designs", "Incidence_(epidemiology)"),
        ("Screening, bias and outbreak investigation", "Sensitivity_and_specificity"),
    ],
    "Biostatistics": [
        ("Normal distribution, p-value and tests of significance", "P-value"),
        ("Sampling, errors and confidence intervals", "Confidence_interval"),
    ],
    "National Health Programs": [
        ("NTEP, NVBDCP and national disease control", "National_Tuberculosis_Elimination_Program"),
    ],
    "Immunization": [
        ("UIP schedule and vaccine types", "Universal_Immunization_Programme"),
        ("AEFI, cold chain and special situations", "Vaccine_hesitancy"),
    ],
    "Cardiology": [
        ("Acute coronary syndromes and heart failure", "Myocardial_infarction"),
        ("Valvular disease, endocarditis and tamponade", "Cardiac_tamponade"),
    ],
    "Pulmonology": [
        ("COPD, asthma and pneumonia", "Chronic_obstructive_pulmonary_disease"),
        ("Pleural disease, TB and interstitial lung disease", "Pleural_effusion"),
    ],
    "Gastroenterology": [
        ("Cirrhosis, GI bleed and hepatitis", "Cirrhosis"),
        ("IBD, pancreatitis and malabsorption", "Pancreatitis"),
    ],
    "Endocrinology": [
        ("Diabetes mellitus and thyroid disorders", "Diabetic_ketoacidosis"),
        ("Adrenal, pituitary and calcium disorders", "Cushing's_syndrome"),
    ],
    "Neurology": [
        ("Stroke and meningitis", "Stroke"),
        ("Seizures, GBS and movement disorders", "Guillain–Barré_syndrome"),
    ],
    "Nephrology": [
        ("AKI, CKD and nephritic-nephrotic syndromes", "Acute_kidney_injury"),
        ("Electrolytes, acid-base and dialysis", "Metabolic_acidosis"),
    ],
    "General Surgery": [
        ("Shock, burns and wound healing", "Parkland_formula"),
        ("Hernia, thyroid and breast (surgical approach)", "Hernia"),
    ],
    "GI Surgery": [
        ("Peptic ulcer, gallbladder and pancreas", "Peptic_ulcer_disease"),
        ("Intestinal obstruction and appendix", "Appendicitis"),
    ],
    "Urology": [
        ("Urolithiasis and BPH", "Kidney_stone"),
        ("Testicular tumours and haematuria", "Testicular_cancer"),
    ],
    "Neurosurgery": [
        ("Head injury and intracranial haemorrhage", "Epidural_hematoma"),
        ("Raised ICP, hydrocephalus and spinal trauma", "Intracranial_pressure"),
    ],
    "Breast and Endocrine Surgery": [
        ("Breast carcinoma", "Breast_cancer"),
        ("Thyroid and parathyroid surgery", "Thyroid_nodule"),
    ],
    "Obstetrics": [
        ("Antenatal care and anaemia in pregnancy", "Prenatal_care"),
        ("Hypertensive disorders and APH/PPH", "Pre-eclampsia"),
    ],
    "Gynaecology": [
        ("AUB, fibroids and endometriosis", "Endometriosis"),
        ("Ovarian tumours and endometrial carcinoma", "Ovarian_cancer"),
    ],
    "Labour and Delivery": [
        ("Mechanism of labour and partograph", "Childbirth"),
        ("Obstructed labour, APH and third stage", "Obstructed_labour"),
    ],
    "Neonatology": [
        ("Neonatal resuscitation and jaundice", "Neonatal_jaundice"),
        ("RDS, TTN and perinatal asphyxia", "Infant_respiratory_distress_syndrome"),
    ],
    "Pediatric Infectious Disease": [
        ("Measles, IMNCI and diarrhoea", "Measles"),
        ("Malaria, dengue and tuberculosis in children", "Dengue_fever"),
    ],
    "Pediatric Growth and Development": [
        ("Growth charts, milestones and puberty", "Child_development_stages"),
        ("SAM, vitamin deficiencies and immunization catch-up", "Malnutrition"),
    ],
    "Cornea and Conjunctiva": [
        ("Conjunctivitis, xerophthalmia and keratitis", "Xerophthalmia"),
        ("Cataract and corneal ulcers", "Cataract"),
    ],
    "Glaucoma": [
        ("Primary open-angle glaucoma", "Glaucoma"),
        ("Acute angle-closure glaucoma", "Glaucoma#Angle-closure"),
    ],
    "Retina": [
        ("Diabetic retinopathy", "Diabetic_retinopathy"),
        ("Retinal vascular occlusions and ARMD", "Central_retinal_artery_occlusion"),
    ],
    "Otology": [
        ("Otitis media and CSOM", "Otitis_media"),
        ("Hearing tests, cholesteatoma and facial nerve", "Cholesteatoma"),
    ],
    "Rhinology": [
        ("Epistaxis and DNS", "Nosebleed"),
        ("Sinusitis, polyps and nasopharyngeal carcinoma", "Nasal_polyp"),
    ],
    "Laryngology": [
        ("Stridor and laryngomalacia", "Laryngomalacia"),
        ("Vocal cord palsy and carcinoma larynx", "Recurrent_laryngeal_nerve"),
    ],
    "Fracture Management": [
        ("Colles, scaphoid and neck of femur", "Colles'_fracture"),
        ("Compartment syndrome and fat embolism", "Compartment_syndrome"),
    ],
    "Bone and Joint Infection": [
        ("Osteomyelitis and septic arthritis", "Osteomyelitis"),
        ("Pott spine and skeletal TB", "Pott_disease"),
    ],
    "Spine Orthopedics": [
        ("Scoliosis and IVDP", "Scoliosis"),
        ("Cauda equina and spinal injuries", "Cauda_equina_syndrome"),
    ],
    "Papulosquamous Disorders": [
        ("Psoriasis and lichen planus", "Psoriasis"),
        ("Pityriasis rosea and eczema", "Pityriasis_rosea"),
    ],
    "Cutaneous Infections": [
        ("Pyoderma and dermatophytes", "Impetigo"),
        ("Leprosy, scabies and viral exanthems", "Leprosy"),
    ],
    "Bullous Disorders": [
        ("Pemphigus vulgaris", "Pemphigus_vulgaris"),
        ("Bullous pemphigoid and dermatitis herpetiformis", "Bullous_pemphigoid"),
    ],
    "Mood Disorders": [
        ("Major depression and bipolar disorder", "Major_depressive_disorder"),
        ("Suicide risk, ECT and antidepressants", "Electroconvulsive_therapy"),
    ],
    "Schizophrenia Spectrum": [
        ("Clinical features and first-rank symptoms", "Schizophrenia"),
        ("Antipsychotics and clozapine monitoring", "Clozapine"),
    ],
    "Anxiety and Substance Use": [
        ("Anxiety disorders and OCD", "Obsessive–compulsive_disorder"),
        ("Alcohol withdrawal and CAGE", "Delirium_tremens"),
    ],
    "General Anesthesia": [
        ("Induction agents and inhalational anaesthetics", "Inhalational_anaesthetic"),
        ("Malignant hyperthermia and monitoring", "Malignant_hyperthermia"),
    ],
    "Regional Anesthesia": [
        ("Spinal and epidural anaesthesia", "Spinal_anaesthesia"),
        ("Local anaesthetic systemic toxicity", "Local_anesthetic_systemic_toxicity"),
    ],
    "Airway Management": [
        ("Mallampati, intubation and difficult airway", "Mallampati_score"),
        ("LMA, RSI and cannot-intubate cannot-oxygenate", "Laryngeal_mask_airway"),
    ],
    "Chest Radiology": [
        ("Silhouette sign, pneumonia and pneumothorax", "Silhouette_sign"),
        ("Pulmonary embolism imaging and collapse", "CT_pulmonary_angiogram"),
    ],
    "Abdominal Radiology": [
        ("Pneumoperitoneum and bowel obstruction", "Pneumoperitoneum"),
        ("Appendicitis, pancreatitis and renal stones imaging", "Abdominal_x-ray"),
    ],
    "Neuroradiology": [
        ("Stroke CT and haemorrhage patterns", "Computed_tomography_of_the_head"),
        ("EDH vs SDH and raised-ICP signs", "Epidural_hematoma"),
    ],
}

# National Health Programs only listed one lesson above on purpose — add second.
LESSON_NAMES["National Health Programs"] = [
    ("NTEP, NVBDCP and national disease control", "National_Tuberculosis_Elimination_Program"),
    ("RCH, RKSK and National Health Mission", "National_Health_Mission"),
]


def plan_for(topic_index: int, lesson_index: int) -> str:
    """Most lessons free; a teaser slice of pro/elite for paywall screens."""
    if lesson_index == 0:
        return "free"
    if topic_index % 11 == 0:
        return "elite"
    if topic_index % 4 == 0:
        return "pro"
    return "free"


def pyq_plan(lesson_plan: str, topic_index: int) -> str:
    if lesson_plan == "elite":
        return "elite"
    if lesson_plan == "pro":
        return "pro"
    if topic_index % 7 == 0:
        return "pro"
    return "free"


def lesson_id(topic: str, name: str) -> str:
    locked = LOCKED_LESSON_IDS.get((topic, name))
    if locked:
        return locked
    subj = TOPIC_SUBJECT[topic]
    lesson_slug = re.sub(r"[^A-Z0-9]+", "-", name.upper()).strip("-")
    if len(lesson_slug) > 32:
        lesson_slug = lesson_slug[:32].rstrip("-")
    return f"L-{PREFIX[subj]}-{lesson_slug}"


def invent_lesson_external_id(subject: str, topic: str, lesson: str) -> str:
    """Must match inventLessonExternalId_ in Apps Script WideSheet/SheetReader."""

    def token(value: str) -> str:
        return re.sub(r"[^a-z0-9]+", "-", value.strip().lower()).strip("-").upper()

    return f"L-{token(subject)}-{token(topic)}-{token(lesson)}"[:80]


def compose_sample(title: str, bullets: list[str]) -> str:
    """KUHS-style long answer: opening, structured body, clinical close."""
    lead = (
        f"{title} is a high-yield KUHS theory topic. Start with a one-line "
        "definition or formation, then organised headings the examiner can tick, "
        "and finish with a clinical correlation or applied anatomy note."
    )
    body = " ".join(bullets)
    close = (
        "In the last two minutes, add a labelled diagram if the paper asks for one, "
        "list two or three exam-favourite complications, and write a one-line "
        "difference from the closest related structure or disease. That pattern "
        "covers both 5-mark short notes and 10-mark structured essays."
    )
    return f"{lead}\n\n{body}\n\n{close}"


def pyq_stem(lesson_name: str, marks: int) -> str:
    if marks >= 10:
        return (
            f"Describe {lesson_name.lower()}. Add a note on the clinically "
            "important applied aspects a KUHS examiner expects."
        )
    return f"Write short notes on {lesson_name.lower()}."


def mcq_bank_for(topic: str, lesson_name: str) -> list[tuple]:
    """Two extra MCQs per lesson. Tuple: stem, A, B, C, D, correct, expl, diff."""
    key = f"{topic}::{lesson_name}"
    bank = EXTRA_MCQS.get(key)
    if bank:
        return bank
    # Fallback so newly added lessons never ship empty.
    return [
        (
            f"Which statement about {lesson_name.lower()} is most accurate in MBBS exams?",
            "It has no clinical correlation",
            "Applied anatomy / physiology of this topic is frequently asked in KUHS",
            "It is obsolete after 2019 NMC curriculum",
            "It is tested only in NEET-PG, never in university papers",
            "B",
            f"{lesson_name} is a standard KUHS theory and viva topic; learn relations and one clinical note.",
            "could",
        ),
        (
            f"A student is asked a 5-mark short note on {lesson_name.lower()}. The best structure is:",
            "Write only a diagram with no headings",
            "Definition, organisation (parts/steps/causes), one clinical point",
            "Copy Harrison chapter verbatim",
            "List drug trade names only",
            "B",
            "Examiners mark headings they can tick: definition, classification or steps, applied aspect.",
            "could",
        ),
    ]


# High-yield extra MCQs keyed by "topic::lesson". Not all lessons need a custom
# pair — the fallback above fills the rest. Custom ones avoid clashing with the
# existing Questions.csv stems (surgical neck, PFK-1, troponin, etc.).
EXTRA_MCQS: dict[str, list[tuple]] = {
    "Upper Limb Anatomy::Brachial plexus": [
        (
            "Erb point is the junction of which structures?",
            "C8 and T1 roots only",
            "C5 and C6 roots / upper trunk",
            "Posterior cord and axillary nerve",
            "Medial cord and ulnar nerve",
            "B",
            "Erb point is on the upper trunk (C5–C6), six nerves meet here; traction causes waiter's-tip posture.",
            "should",
        ),
        (
            "The long thoracic nerve arises from which roots?",
            "C5, C6, C7",
            "C8, T1",
            "C3, C4",
            "T1, T2",
            "A",
            "Long thoracic (C5–C7) supplies serratus anterior; injury causes winged scapula.",
            "could",
        ),
    ],
    "Upper Limb Anatomy::Humerus fractures": [
        (
            "A fracture of the medial epicondyle of the humerus risks which nerve?",
            "Radial",
            "Ulnar",
            "Axillary",
            "Musculocutaneous",
            "B",
            "Ulnar nerve lies behind the medial epicondyle (funny bone); supracondylar fractures more often injure the median/anterior interosseous or brachial artery.",
            "could",
        ),
        (
            "Holstein–Lewis fracture is a fracture of the:",
            "Surgical neck of humerus",
            "Distal third of the humeral shaft associated with radial nerve palsy",
            "Scaphoid waist",
            "Clavicle middle third",
            "B",
            "A spiral fracture of the distal humeral shaft can entrap the radial nerve as it pierces the lateral intermuscular septum.",
            "must",
        ),
    ],
    "Head and Neck Anatomy::Larynx": [
        (
            "Which nerve supplies cricothyroid?",
            "Recurrent laryngeal nerve",
            "External laryngeal nerve",
            "Internal laryngeal nerve",
            "Glossopharyngeal nerve",
            "B",
            "Cricothyroid is the only intrinsic laryngeal muscle supplied by the external laryngeal nerve (superior laryngeal); others are recurrent laryngeal.",
            "could",
        ),
        (
            "The rima glottidis is widest during:",
            "Quiet inspiration",
            "Forced inspiration (abduction of cords)",
            "Phonation",
            "Swallowing with cords adducted only",
            "B",
            "Posterior cricoarytenoids abduct the cords; rima is widest in deep inspiration.",
            "should",
        ),
    ],
}


def custom_pyq_facts() -> dict[str, tuple[str, int, list[str]]]:
    """lesson_id → (stem, marks, bullets). Missing IDs get a generated stem."""
    facts: dict[str, tuple[str, int, list[str]]] = {}

    def add(topic: str, lesson: str, stem: str, marks: int, bullets: list[str]) -> None:
        facts[lesson_id(topic, lesson)] = (stem, marks, bullets)

    add(
        "Upper Limb Anatomy",
        "Brachial plexus",
        "Describe the formation of the brachial plexus. Add a note on Erb palsy.",
        10,
        [
            "Kept as the existing sheet sample — generator skips rewriting this PYQ."
        ],
    )
    add(
        "Upper Limb Anatomy",
        "Humerus fractures",
        "A fracture of the surgical neck of the humerus. Enumerate structures at risk.",
        5,
        [],
    )
    add(
        "Head and Neck Anatomy",
        "Larynx",
        "Describe the cartilages, cavity and nerve supply of the larynx. Add a note on the safety muscle.",
        10,
        [
            "The larynx lies at C3–C6 and is the sphincter and organ of phonation.",
            "Unpaired cartilages are thyroid, cricoid and epiglottis; paired are arytenoid, corniculate and cuneiform.",
            "The cavity is divided by vestibular and vocal folds into vestibule, ventricle and infraglottic cavity.",
            "Posterior cricoarytenoid is the only abductor of the vocal cords and is called the safety muscle of the larynx.",
            "All intrinsic muscles except cricothyroid are supplied by the recurrent laryngeal nerve; cricothyroid by the external laryngeal nerve.",
            "Sensory supply above the vocal folds is internal laryngeal; below is recurrent laryngeal.",
            "Applied: recurrent laryngeal palsy causes hoarseness; bilateral abductor palsy threatens the airway.",
        ],
    )
    add(
        "Head and Neck Anatomy",
        "Thyroid gland and triangles of the neck",
        "Describe the thyroid gland. Add a note on its blood supply and the nerves at risk during thyroidectomy.",
        10,
        [
            "The thyroid is an endocrine gland in the anterior triangle, investing two lobes and an isthmus over tracheal rings 2–4.",
            "It is enclosed in pretracheal fascia and moves with deglutition.",
            "Arterial supply is superior thyroid (external carotid) and inferior thyroid (thyrocervical trunk); a thyroid ima artery may arise from the aorta or brachiocephalic trunk.",
            "Superior thyroid artery is close to the external laryngeal nerve; inferior thyroid artery is close to the recurrent laryngeal nerve — ligate vessels near the gland.",
            "Venous drainage is superior and middle thyroid veins to internal jugular, inferior thyroid veins to brachiocephalic veins.",
            "Lymphatics follow the arteries to prelaryngeal, pretracheal and deep cervical nodes.",
            "Anterior triangle subdivisions: submental, submandibular, carotid and muscular; posterior triangle is occipital and supraclavicular.",
        ],
    )
    add(
        "Neuroanatomy",
        "Visual pathway",
        "Trace the visual pathway from retina to cortex. Add a note on visual field defects.",
        10,
        [
            "Photoreceptors → bipolar cells → retinal ganglion cells whose axons form the optic nerve.",
            "Fibres from the nasal retina decussate in the optic chiasma; temporal fibres stay ipsilateral.",
            "Optic tract wraps the cerebral peduncle and synapses in the lateral geniculate nucleus.",
            "Geniculocalcarine (optic) radiation: upper field via Meyer loop in temporal lobe, lower field via parietal lobe, to primary visual cortex (area 17) on the lips of the calcarine sulcus.",
            "Macular fibres go to the posterior occipital pole.",
            "Chiasmal compression (pituitary) causes bitemporal hemianopia; optic tract or radiation lesions cause contralateral homonymous hemianopia; occipital lesions may spare macula.",
        ],
    )
    add(
        "Neuroanatomy",
        "Circle of Willis and cranial nerve nuclei",
        "Describe the circle of Willis. Add a note on midbrain cranial-nerve nuclei.",
        10,
        [
            "The circulus arteriosus is an anastomotic polygon in the interpeduncular cistern at the base of the brain.",
            "Anterior communicating artery joins the two anterior cerebrals; posterior communicating arteries join internal carotid to posterior cerebral.",
            "It equalises flow if a proximal vessel is stenosed, but perforators (lenticulostriates, thalamoperforators) are end-arteries.",
            "Berry aneurysms favour anterior communicating, posterior communicating and middle cerebral bifurcations.",
            "Midbrain: oculomotor nucleus and Edinger–Westphal at superior colliculus level; trochlear nucleus at inferior colliculus (the only dorsal CN exit, fully crossed).",
            "Weber syndrome (basis pedunculi) is ipsilateral III palsy plus contralateral hemiparesis.",
        ],
    )
    add(
        "Embryology",
        "Gastrulation and notochord",
        "Describe gastrulation. Add a note on the notochord and sacrococcygeal teratoma.",
        10,
        [
            "Gastrulation in week 3 converts the bilaminar disc into a trilaminar disc.",
            "The primitive streak appears in the caudal epiblast; the primitive node is at its cranial end.",
            "Epiblast cells ingress through the streak to form definitive endoderm and intraembryonic mesoderm; remaining epiblast is ectoderm.",
            "The notochordal process extends from the node to the prechordal plate and becomes the notochord, inducing the neural plate.",
            "Remnants of primitive streak may form a sacrococcygeal teratoma, more common in female infants.",
            "Failure of gastrulation can cause caudal dysgenesis (sirenomelia) especially in diabetic mothers.",
        ],
    )
    add(
        "Embryology",
        "Pharyngeal arches and fetal circulation",
        "Enumerate the derivatives of the pharyngeal arches. Add a note on fetal circulation and changes at birth.",
        10,
        [
            "Six arches appear; the fifth is rudimentary. Each has a nerve, artery and cartilage.",
            "Arch 1 (V): mandible, malleus, incus, muscles of mastication. Arch 2 (VII): stapes, styloid, lesser hyoid horn, muscles of facial expression.",
            "Arch 3 (IX): greater hyoid horn and stylopharyngeus. Arches 4 and 6 (X): laryngeal cartilages, pharyngeal constrictors, intrinsic larynx.",
            "Treacher Collins and Pierre Robin relate to first-arch problems; DiGeorge to 3rd/4th pouch (thymus, parathyroids).",
            "Fetal shunts: ductus venosus (liver bypass), foramen ovale (RA to LA), ductus arteriosus (pulmonary trunk to aorta).",
            "At birth lungs expand, PVR falls, foramen ovale closes functionally, ductus arteriosus closes under rising PaO2 and falling PGE2 — remnant is ligamentum arteriosum.",
        ],
    )
    add(
        "Thorax Anatomy",
        "Heart and coronary arteries",
        "Describe the blood supply of the heart. Add a note on dominance and referred pain of angina.",
        10,
        [
            "Right and left coronary arteries arise from the anterior and left posterior aortic sinuses.",
            "RCA runs in the right AV groove, gives SA nodal (in ~60%), right marginal, and usually the posterior descending artery in right dominance.",
            "LCA divides into LAD (anterior IV groove, diagonals, septal perforators) and circumflex (left AV groove, obtuse marginals).",
            "Venous drainage is mainly the coronary sinus (great, middle, small cardiac veins) into the right atrium; anterior cardiac veins drain directly to RA.",
            "Most people are right-dominant (PDA from RCA). Left dominance (PDA from LCx) is less common.",
            "Ischaemic pain is referred to the left arm, jaw and epigastrium via T1–T4 sympathetics sharing dermatomes with the heart.",
        ],
    )
    add(
        "Thorax Anatomy",
        "Bronchopulmonary segments and mediastinum",
        "What is a bronchopulmonary segment? Enumerate segments of the right lung. Add a note on the contents of the superior mediastinum.",
        10,
        [
            "A bronchopulmonary segment is a portion of lung supplied by a tertiary (segmental) bronchus and a segmental pulmonary artery, separated by connective-tissue septa with pulmonary veins in the intersegmental planes.",
            "It is the surgical unit of the lung — a segmentectomy is possible.",
            "Right lung has 10 segments: upper lobe apical, posterior, anterior; middle lateral and medial; lower superior plus medial, anterior, lateral, posterior basal.",
            "Left lung typically 8–10 because of fusion (e.g. upper-lobe apicoposterior, lingula superior and inferior).",
            "Aspiration when supine prefers the posterior segment of the upper lobe or superior segment of the lower lobe.",
            "Superior mediastinum (thoracic inlet to T4 plane): thymus, brachiocephalic veins and SVC, aortic arch and branches, trachea, oesophagus, phrenic and vagus, left recurrent laryngeal, thoracic duct.",
        ],
    )
    add(
        "Abdomen Anatomy",
        "Inguinal canal and hernia",
        "Describe the inguinal canal. Differentiate direct and indirect inguinal hernia.",
        10,
        [
            "The inguinal canal is an oblique 4 cm passage in the lower anterior abdominal wall, above the inguinal ligament, from deep to superficial inguinal rings.",
            "Contents: spermatic cord (or round ligament) and ilioinguinal nerve (which enters the canal rather than the deep ring).",
            "Boundaries (MALT): roof — muscles (internal oblique, transversus); anterior — aponeurosis of external oblique (and internal oblique laterally); floor — inguinal ligament and lacunar ligament; posterior — transversalis fascia, reinforced medially by conjoint tendon.",
            "Indirect hernia leaves through the deep ring, lateral to inferior epigastric vessels, and may follow the processus vaginalis into the scrotum; it is often congenital.",
            "Direct hernia bulges through Hesselbach triangle, medial to inferior epigastric vessels, and is acquired from posterior-wall weakness.",
            "Coverings differ: indirect has extra peritoneal processes along the cord; both can strangulate.",
        ],
    )
    add(
        "Abdomen Anatomy",
        "Portal vein and extrahepatic biliary tree",
        "Describe the formation, course and tributaries of the portal vein. Add a note on portosystemic anastomoses.",
        10,
        [
            "The portal vein forms behind the neck of the pancreas by union of superior mesenteric and splenic veins, and is about 8 cm long.",
            "It runs in the free edge of the lesser omentum (right free border) as the posterior member of the portal triad with hepatic artery and bile duct, then divides at the porta hepatis.",
            "It carries ~75% of hepatic blood flow, nutrient-rich and deoxygenated.",
            "Portosystemic anastomoses: lower oesophagus (left gastric–azygos, site of varices), umbilicus (paraumbilical–superior epigastric, caput medusae), rectum (superior–middle/inferior rectal, anorectal varices), retroperitoneum and bare area of liver.",
            "Clinically, portal hypertension from cirrhosis presents with variceal bleed, splenomegaly and ascites.",
            "Extrahepatic bile duct: right and left hepatic ducts → common hepatic + cystic duct → CBD, which joins the pancreatic duct at the ampulla of Vater in D2.",
        ],
    )
    add(
        "Lower Limb Anatomy",
        "Femoral triangle and adductor canal",
        "Describe the femoral triangle. Add a note on the adductor (Hunter) canal.",
        10,
        [
            "Femoral triangle is in the upper thigh: base is inguinal ligament, lateral sartorius, medial adductor longus; floor is iliopsoas, pectineus and adductor longus; roof is fascia lata, cribriform fascia and skin.",
            "Contents lateral to medial (NAVY): femoral Nerve, Artery, Vein, Y-empty (femoral canal with lymph node of Cloquet).",
            "Femoral sheath encloses artery, vein and canal, not the nerve.",
            "Femoral hernia is more common in females, appears below and lateral to the pubic tubercle, and has a high strangulation risk at the rigid femoral ring.",
            "Adductor canal (Hunter) runs from the apex of the triangle to the adductor hiatus, under sartorius, with vastus medialis lateral and adductors posterior.",
            "It contains femoral artery and vein, saphenous nerve and nerve to vastus medialis; a site for adductor-canal block and for femoral-artery ligation in some trauma protocols.",
        ],
    )
    add(
        "Lower Limb Anatomy",
        "Sciatic nerve and gluteal region",
        "Describe the sciatic nerve. Add a note on intramuscular injection in the gluteal region.",
        10,
        [
            "The sciatic nerve (L4–S3) is the largest nerve, leaving the pelvis via the greater sciatic foramen below piriformis.",
            "It runs on the posterior thigh under biceps femoris, supplying hamstrings (tibial part to semimembranosus, semitendinosus and long head of biceps; common peroneal to short head of biceps).",
            "It divides at the superior popliteal fossa (variable) into tibial and common peroneal nerves.",
            "Piriformis syndrome and posterior hip dislocation can compress it; a misplaced IM injection can cause foot drop.",
            "Safe IM site is the upper outer quadrant of the buttock, or preferably the ventrogluteal (gluteus medius) site, avoiding the lower medial quadrant where the nerve lies.",
            "Inferior gluteal artery and nerve to quadratus femoris are related in the deep gluteal region; Trendelenburg gait follows superior gluteal nerve injury (gluteus medius/minimus).",
        ],
    )
    add(
        "Cardiology",
        "Acute coronary syndromes and heart failure",
        "Discuss the diagnosis and immediate management of ST-elevation myocardial infarction. Add a note on HFrEF drug therapy that improves survival.",
        10,
        [
            "STEMI is myocardial necrosis from acute coronary occlusion, usually plaque rupture plus thrombus.",
            "Diagnosis: ischaemic symptoms plus ST elevation in two contiguous leads (or new LBBB) and a rise/fall of troponin.",
            "Immediate care: MONA is outdated as a bundle — give aspirin 300 mg chewed, P2Y12 inhibitor, anticoagulation, high-intensity statin, oxygen only if hypoxic, and urgent reperfusion.",
            "Primary PCI is preferred if it can be done within guideline time; otherwise fibrinolysis if no contraindication, then transfer.",
            "Complications: arrhythmia, pump failure, mechanical rupture, Dressler syndrome later.",
            "HFrEF survival drugs: ARNI or ACEI/ARB, evidence-based beta-blocker, mineralocorticoid antagonist, SGLT2 inhibitor — the four pillars. Loop diuretics are for congestion, not mortality.",
        ],
    )
    add(
        "Obstetrics",
        "Hypertensive disorders and APH/PPH",
        "Define pre-eclampsia. Discuss management of eclampsia. Add a note on PPH.",
        10,
        [
            "Pre-eclampsia is new hypertension after 20 weeks with proteinuria or end-organ dysfunction (thrombocytopenia, raised creatinine, liver enzymes, pulmonary oedema, cerebral/visual symptoms).",
            "Severe features and eclampsia (seizures) are obstetric emergencies. Delivery is the definitive treatment after stabilisation.",
            "Eclampsia: airway, left lateral tilt, magnesium sulfate (Pritchard IM or Zuspan IV) to control seizures, antihypertensives (labetalol, nifedipine, hydralazine) for BP, and plan delivery.",
            "Do not use diazepam as first-line seizure control in eclampsia.",
            "PPH is blood loss ≥500 mL after vaginal birth or ≥1000 mL after CS (or any amount causing hemodynamic compromise).",
            "Four Ts: tone (atony — uterotonics, bimanual compression), trauma (tears), tissue (retained placenta), thrombin (coagulopathy). Uterine balloon, compression sutures and stepwise devascularisation follow if needed.",
        ],
    )
    add(
        "Cardiovascular Physiology",
        "Cardiac cycle and heart sounds",
        "Describe the cardiac cycle. Add a note on the first and second heart sounds.",
        10,
        [
            "The cardiac cycle is the sequence of mechanical events in one heartbeat, about 0.8 s at 75/min (systole ~0.3 s, diastole ~0.5 s).",
            "Atrial systole tops up ventricular filling (a wave, PR interval). Isovolumetric contraction begins with AV valve closure (S1) when ventricular pressure exceeds atrial pressure.",
            "Ejection opens the semilunar valves; most stroke volume is expelled in the rapid-ejection phase.",
            "Isovolumetric relaxation follows semilunar closure (S2); ventricular filling then occurs (rapid filling, diastasis, atrial kick).",
            "S1 is AV valve closure (M1 before T1); S2 is aortic then pulmonary closure (A2-P2; physiological split in inspiration).",
            "S3 is rapid-filling (can be normal in the young; pathological in failure). S4 is atrial kick against a stiff ventricle.",
        ],
    )
    add(
        "Cardiovascular Physiology",
        "Jugular venous pulse and ECG basics",
        "Describe the jugular venous pulse waves. Add a note on the ECG leads and a normal PR interval.",
        5,
        [
            "JVP inspects the right internal jugular, reflecting right-atrial pressure, with the patient at 45°.",
            "a wave: atrial contraction. c wave: tricuspid bulging in isovolumetric contraction. x descent: atrial relaxation and downward valve movement.",
            "v wave: atrial filling against a closed tricuspid. y descent: emptying into the ventricle when the tricuspid opens.",
            "Raised JVP with absent y (tamponade), giant v waves (TR), cannon a waves (AV dissociation), lost a wave (AF).",
            "ECG: standard 12 leads; PR 0.12–0.20 s (AV conduction); QRS <0.12 s; ST and T for ischaemia.",
        ],
    )
    add(
        "Respiratory Physiology",
        "Lung volumes and spirometry",
        "Define the lung volumes and capacities. Which cannot be measured by spirometry? Add a note on FEV1/FVC.",
        10,
        [
            "Tidal volume ~500 mL; IRV and ERV are extra inspired/expired volumes; residual volume remains after maximal expiration.",
            "Vital capacity = TV+IRV+ERV. TLC = VC+RV. FRC = ERV+RV (the resting volume).",
            "RV, FRC and TLC need dilution or body plethysmography — spirometry cannot measure RV.",
            "FEV1/FVC is reduced in obstruction (COPD, asthma) and normal or high in restriction (fibrosis) where both FEV1 and FVC fall together.",
            "Peak expiratory flow is effort-dependent and used in asthma action plans.",
            "Closing volume rises with age and small-airway disease.",
        ],
    )
    add(
        "Respiratory Physiology",
        "Oxygen transport and hypoxia",
        "Describe oxygen transport in blood. Classify hypoxia with one example of each.",
        10,
        [
            "About 97% of oxygen is bound to haemoglobin; 3% is dissolved (what PaO2 measures).",
            "Each gram of Hb binds 1.34 mL O2; oxygen content ≈ (1.34 × Hb × SaO2) + 0.003×PaO2.",
            "The O2–Hb curve is sigmoid; a right shift (raised CO2, H+, 2,3-BPG, temperature — Bohr effect) unloads O2 in tissues.",
            "Hypoxic hypoxia: low PaO2 (high altitude, COPD). Anaemic hypoxia: low Hb or CO poisoning (PaO2 may be normal).",
            "Stagnant hypoxia: low flow (shock, heart failure). Histotoxic: cyanide blocking cytochrome oxidase.",
            "Cyanosis needs about 5 g/dL deoxygenated Hb and may be absent in severe anaemia.",
        ],
    )
    add(
        "Renal Physiology",
        "GFR and clearance",
        "Define GFR and clearance. Why is inulin the gold standard? Add a note on creatinine clearance.",
        10,
        [
            "GFR is the volume of plasma filtered by glomeruli per unit time, normally ~125 mL/min (180 L/day) in a young adult.",
            "Clearance of a substance = U×V / P. If the substance is freely filtered and neither reabsorbed nor secreted, clearance equals GFR.",
            "Inulin meets those criteria and is the gold-standard GFR marker; it is not used routinely.",
            "Creatinine is produced steadily from muscle, freely filtered, with a little tubular secretion, so creatinine clearance slightly overestimates GFR.",
            "eGFR equations (CKD-EPI) use serum creatinine, age and sex for clinical staging of CKD.",
            "PAH at low concentration is nearly completely extracted, so PAH clearance estimates effective renal plasma flow.",
        ],
    )
    add(
        "Renal Physiology",
        "Countercurrent mechanism and ADH",
        "Describe the countercurrent multiplier. Add a note on the action of ADH on the collecting duct.",
        10,
        [
            "The loop of Henle and vasa recta create and preserve a medullary osmotic gradient from 300 mOsm at the cortex to ~1200 mOsm at the papilla.",
            "Thick ascending limb actively pumps NaCl and is impermeable to water (diluting segment). Descending limb is water-permeable, so tubular fluid equilibrates with the interstitium.",
            "Urea recycling from the inner medullary collecting duct adds to deep medullary osmolality.",
            "Vasa recta are a countercurrent exchanger that remove water and solute without washing out the gradient.",
            "ADH (vasopressin) acts on V2 receptors of principal cells, raises cAMP, and inserts aquaporin-2 on the apical membrane so water is reabsorbed.",
            "Without ADH (central DI) large volumes of dilute urine are passed; V2-receptor or AQP2 defects cause nephrogenic DI.",
        ],
    )
    add(
        "General Pathology",
        "Cell injury, necrosis and apoptosis",
        "Classify necrosis with examples. Differentiate apoptosis from necrosis.",
        10,
        [
            "Necrosis is unregulated cell death with membrane rupture and inflammation; apoptosis is programmed death without inflammation.",
            "Coagulative necrosis: infarcts of solid organs (except brain). Liquefactive: brain infarct and abscess. Caseous: TB. Fat: pancreatitis, breast. Fibrinoid: immune vasculitis, malignant hypertension. Gangrene: ischaemic necrosis plus putrefaction.",
            "Apoptosis: cell shrinkage, pyknosis, karyorrhexis, apoptotic bodies, caspase cascade, DNA laddering.",
            "Intrinsic pathway is mitochondrial (Bcl-2 family, cytochrome c, Apaf-1). Extrinsic is Fas/TNF death receptors.",
            "Reversible injury shows cellular swelling and fatty change; irreversible shows membrane damage and mitochondrial permeability transition.",
            "Free radicals (ROS) injure lipids, proteins and DNA; scavengers include SOD, catalase, glutathione peroxidase, vitamins C and E.",
        ],
    )
    add(
        "Hematopathology",
        "Leukemias and lymphomas",
        "Classify leukemias. Add a note on the Philadelphia chromosome and Reed–Sternberg cells.",
        10,
        [
            "Leukemias are acute or chronic, myeloid or lymphoid, based on onset and lineage of the blast or mature cell.",
            "ALL is the commonest childhood leukaemia; AML is more often adult and may show Auer rods.",
            "CML is defined by t(9;22) BCR-ABL (Philadelphia chromosome), treated with tyrosine-kinase inhibitors such as imatinib.",
            "CLL is a disease of older adults, smudge cells, CD5+ B cells; may transform (Richter).",
            "Reed–Sternberg cells (CD15+, CD30+) define classic Hodgkin lymphoma; NHL is a mixed group (diffuse large B-cell, follicular t(14;18) BCL2, Burkitt t(8;14) MYC).",
            "Staging (Ann Arbor) and B symptoms (fever, night sweats, weight loss) still appear in university answers.",
        ],
    )
    add(
        "Bacteriology",
        "Gram-positive pathogens and mycobacteria",
        "Describe Mycobacterium tuberculosis. Add a note on laboratory diagnosis under NTEP.",
        10,
        [
            "M. tuberculosis is an acid-fast, aerobic, slow-growing bacillus with mycolic acids that retain Ziehl–Neelsen / auramine stain.",
            "Transmission is airborne droplets; primary infection is a Ghon focus, often with hilar nodes (Ghon complex).",
            "Virulence includes cord factor and ability to survive in macrophages; tissue response is caseating granulomas.",
            "NTEP prefers molecular WHO-recommended rapid diagnostics (CBNAAT / TrueNat) on sputum over serology, which is banned for TB diagnosis.",
            "LJ culture and MGIT remain for DST in selected cases. Mantoux and IGRA detect infection, not active disease.",
            "Drug-resistant TB (RR/MDR/pre-XDR/XDR) is defined by resistance patterns and treated with all-oral longer or shorter regimens per current guidelines.",
        ],
    )
    add(
        "Cardiovascular Pharmacology",
        "Antihypertensives and heart-failure drugs",
        "Classify antihypertensive drugs. Add a note on ACE inhibitors and drugs that improve survival in HFrEF.",
        10,
        [
            "First-line groups: thiazides, dihydropyridine CCBs, ACEI/ARBs; beta-blockers when there is a compelling indication (IHD, HFrEF, rate control).",
            "ACEI block angiotensin-II formation: fall in TPR, less aldosterone, less cardiac remodelling. Cough and angioedema from kinin potentiation; contraindicated in bilateral renal-artery stenosis and pregnancy.",
            "Enalapril is a prodrug; captopril and lisinopril are active. ARBs (losartan) avoid cough.",
            "HFrEF mortality benefit: ARNI/ACEI/ARB, carvedilol/bisoprolol/metoprolol XL, spironolactone/eplerenone, SGLT2 inhibitors.",
            "Loop diuretics treat congestion. Digoxin may reduce hospitalisation but is not first-line for survival.",
            "Hypertensive emergency needs controlled reduction (labetalol, nicardipine, nitroprusside) — not a sudden plunge in BP.",
        ],
    )
    add(
        "Epidemiology",
        "Measures of disease frequency and study designs",
        "Define incidence and prevalence. Compare case-control and cohort studies.",
        10,
        [
            "Incidence is new cases in a population in a defined time. Prevalence is all existing cases at a point (or period).",
            "Prevalence ≈ incidence × duration for a stable disease. Screening raises prevalence of detected disease.",
            "Cohort studies follow exposure to outcome and can give relative risk and incidence; they are costly and slow for rare outcomes.",
            "Case-control studies sample on disease status, are good for rare diseases, and yield an odds ratio, not a true RR.",
            "RCTs assign intervention and are the gold standard for therapy; bias is reduced by randomisation, blinding and ITT analysis.",
            "Confounding, selection bias and information bias must be named in a KUHS answer with one example each.",
        ],
    )
    add(
        "Pulmonology",
        "COPD, asthma and pneumonia",
        "Differentiate COPD and asthma. Add a note on community-acquired pneumonia treatment principles.",
        10,
        [
            "COPD is persistent airflow limitation, usually progressive, from smoking or biomass smoke, with FEV1/FVC <0.7 after bronchodilator.",
            "Asthma is reversible, often atopic, with diurnal variation, eosinophilic inflammation and good steroid response.",
            "COPD phenotypes include chronic bronchitis and emphysema; exacerbations are treated with oxygen (target sats 88–92% in at-risk patients), bronchodilators, steroids, and antibiotics when indicated.",
            "Pneumonia: acute infection of lung parenchyma. CAP commonest organism is S. pneumoniae.",
            "CURB-65 (confusion, urea, RR, BP, age) helps site-of-care. Empiric antibiotics follow national/hospital protocol and local resistance.",
            "Oxygen, fluids, DVT prophylaxis and review of complications (parapneumonic effusion, abscess) complete the answer.",
        ],
    )
    add(
        "General Surgery",
        "Shock, burns and wound healing",
        "Classify shock. Describe the Parkland formula and the rule of nines.",
        10,
        [
            "Shock is inadequate tissue perfusion: hypovolaemic, cardiogenic, distributive (septic/anaphylactic/neurogenic) and obstructive (tamponade, tension pneumothorax, massive PE).",
            "Clinical features: tachycardia, hypotension, oliguria, altered mentation, cool or warm skin depending on type.",
            "Rule of nines estimates adult TBSA (head 9, each arm 9, each leg 18, anterior trunk 18, posterior 18, perineum 1).",
            "Parkland: 4 mL Ringer lactate × kg × %TBSA in 24 h from time of burn; half in the first 8 h, rest in 16 h; titrate to urine output ~0.5–1 mL/kg/h.",
            "Wound healing: haemostasis, inflammation, proliferation (granulation, collagen, contraction) and remodelling. Primary, secondary and tertiary intention.",
            "Factors delaying healing: infection, ischaemia, steroids, diabetes, malnutrition, foreign body.",
        ],
    )
    add(
        "Labour and Delivery",
        "Mechanism of labour and partograph",
        "Describe the mechanism of normal labour in occipito-anterior position. Add a note on the partograph.",
        10,
        [
            "Labour is the process by which the fetus, placenta and membranes are expelled through the birth canal.",
            "Cardinal movements in OA: engagement, descent, flexion, internal rotation, extension (crowning), restitution, external rotation, expulsion.",
            "The smallest engaging diameter in well-flexed vertex is suboccipitobregmatic (~9.5 cm).",
            "WHO/modified partograph plots cervical dilatation and descent against time, with alert and action lines, plus fetal heart, moulding, contractions, fluids and drugs.",
            "Crossing the action line prompts reassessment for augmentation, CS or other intervention — it is a decision aid, not a rigid rule.",
            "Four stages: first (latent + active cervical dilatation), second (expulsive), third (placenta), fourth (1–2 h observation for PPH).",
        ],
    )
    add(
        "Neonatology",
        "Neonatal resuscitation and jaundice",
        "Outline neonatal resuscitation (NRP). Add a note on physiological and pathological jaundice.",
        10,
        [
            "Delayed cord clamping when appropriate, dry and stimulate, maintain temperature, open airway, assess breathing and heart rate.",
            "If HR <100 or apnoea: PPV with room air (21%) initially in term babies; add oxygen and chest compressions if HR <60 after effective ventilation, with 3:1 ratio.",
            "Adrenaline via UVC if HR stays <60. Always ask about meconium, gestational age and tone.",
            "Physiological jaundice appears after 24 h, peaks day 3–4 in term, is unconjugated, and the baby is well.",
            "Pathological: <24 h, rapid rise, conjugated, anaemia, sick infant — think haemolysis, sepsis, obstruction, metabolic disease.",
            "Phototherapy converts bilirubin to lumirubin; exchange transfusion for dangerous levels or hydrops. Always give IM vitamin K at birth to prevent HDN.",
        ],
    )
    add(
        "Glaucoma",
        "Primary open-angle glaucoma",
        "Define glaucoma. Discuss clinical features and treatment of primary open-angle glaucoma.",
        10,
        [
            "Glaucoma is a progressive optic neuropathy with characteristic disc changes and visual-field loss, often but not always with raised IOP.",
            "POAG is chronic, bilateral, with an open angle, typically asymptomatic until field loss is advanced — hence screening of high-risk groups.",
            "Disc: increased cup-disc ratio, vertical elongation of cup, bayoneting, laminar dot sign, disc haemorrhage.",
            "IOP is measured by Goldmann applanation; fields by perimetry; OCT of RNFL aids follow-up.",
            "First-line drops are prostaglandin analogues (latanoprost) increasing uveoscleral outflow; then beta-blockers, alpha-agonists, carbonic-anhydrase inhibitors.",
            "Laser trabeculoplasty or trabeculectomy when drops fail. Steroids can raise IOP (steroid responder).",
        ],
    )
    add(
        "Otology",
        "Otitis media and CSOM",
        "Classify otitis media. Discuss complications of CSOM.",
        10,
        [
            "Acute otitis media is a rapid middle-ear infection, usually viral then S. pneumoniae / H. influenzae / M. catarrhalis in children, with pain, fever and a red bulging drum.",
            "OME (glue ear) is effusion without acute infection and is a common cause of hearing loss in children.",
            "CSOM is chronic discharge through a perforation >6–12 weeks: tubo-tympanic (safe) vs attico-antral (unsafe, cholesteatoma).",
            "Cholesteatoma is erosive squamous epithelium and can cause facial palsy, labyrinthitis, mastoiditis, meningitis, brain abscess, sigmoid-sinus thrombosis.",
            "Unsafe CSOM needs imaging and mastoid exploration; safe CSOM may be managed with aural toilet, drops, and later tympanoplasty.",
            "Never syringe an unsafe ear. Tuning-fork tests: negative Rinne plus Weber to that ear suggests conductive loss.",
        ],
    )
    add(
        "Fracture Management",
        "Colles, scaphoid and neck of femur",
        "Describe Colles fracture. Add a note on scaphoid fracture and Garden classification of neck-of-femur fractures.",
        10,
        [
            "Colles is an extra-articular distal-radius fracture with dorsal angulation and radial shortening after FOOSH in osteoporotic elderly — dinner-fork deformity.",
            "Complications: malunion, stiffness, CRPS, EPL rupture, carpal tunnel, ulnar styloid issues.",
            "Scaphoid: snuffbox tenderness after FOOSH; blood supply is distal to proximal, so proximal-pole fractures risk AVN and nonunion. Immobilise and image (scaphoid series / MRI).",
            "Neck of femur: Garden I–II undisplaced, III–IV displaced. Young: urgent reduction and fixation. Elderly displaced: arthroplasty (hemi or THR per fitness and fracture type).",
            "Intracapsular vs extracapsular (intertrochanteric) matters because of blood supply and implant choice (DHS, nail).",
            "Fat embolism after long-bone fractures presents 24–72 h with hypoxia, petechiae and cerebral signs.",
        ],
    )
    add(
        "Papulosquamous Disorders",
        "Psoriasis and lichen planus",
        "Describe the clinical types of psoriasis. Add a note on Auspitz sign and Wickham striae.",
        10,
        [
            "Psoriasis is a chronic T-cell mediated papulosquamous disease with well-defined erythematous plaques and silvery scale, classically on extensors and scalp.",
            "Types: plaque (vulgaris), guttate (post-streptococcal in youth), inverse, pustular, erythrodermic, nail (pitting, oil drop, onycholysis) and arthropathy.",
            "Auspitz: pinpoint bleeding on removing scale. Koebner phenomenon. Candle-grease sign.",
            "Lichen planus: 6 Ps — planar, purple, polygonal, pruritic, papules, plaques; Wickham striae; oral and genital mucosa; hypertrophic LP on shins.",
            "Histology of psoriasis: parakeratosis, Munro microabscesses, regular acanthosis. LP: band-like lichenoid infiltrate, saw-tooth rete, civatte bodies, hypergranulosis.",
            "Treat psoriasis by extent: topicals (steroid, vitamin D analogues), phototherapy, systemics (methotrexate, ciclosporin, acitretin) and biologics in severe disease. Avoid systemic steroids as rebound is fierce.",
        ],
    )
    add(
        "Mood Disorders",
        "Major depression and bipolar disorder",
        "Enumerate the features of a major depressive episode. Outline treatment of bipolar mania.",
        10,
        [
            "MDE: ≥2 weeks of depressed mood or anhedonia plus sleep/appetite change, fatigue, guilt, poor concentration, psychomotor change or suicidal ideas, with impairment.",
            "Always assess suicide risk (intent, plan, protective factors) and psychotic features.",
            "SSRIs are first-line antidepressants in primary care; counsel about 2–4 week latency and activation. ECT is for severe, psychotic, or catatonic depression and pregnancy when indicated.",
            "Bipolar I mania: elevated/irritable mood, increased energy, decreased need for sleep, grandiosity, rapid speech, recklessness, possible psychosis, ≥7 days or hospitalisation.",
            "Treat mania with lithium, valproate or an atypical antipsychotic; never an antidepressant alone.",
            "Lithium needs serum levels, TSH and renal monitoring; toxicity is more likely with thiazides, ACEI and NSAIDs.",
        ],
    )
    add(
        "General Anesthesia",
        "Induction agents and inhalational anaesthetics",
        "Compare propofol, thiopentone, ketamine and etomidate. Add a note on MAC.",
        10,
        [
            "Propofol: GABA-A potentiation, rapid onset/offset, antiemetic, causes vasodilation and hypotension, pain on injection, infusion syndrome with prolonged high dose.",
            "Thiopentone: barbiturate, reduces ICP, intra-arterial injection is disastrous, contraindicated in porphyria.",
            "Ketamine: NMDA antagonist, dissociative anaesthesia, preserves respiration and sympathetic tone, good for shock and asthmatics, emergence delirium, raises ICP/IOP in classic teaching (nuance exists).",
            "Etomidate: most cardiostable, inhibits 11-β-hydroxylase (adrenal suppression) — avoid infusions in sepsis.",
            "MAC is the alveolar concentration preventing movement in 50% of subjects; it falls with age, hypothermia, opioids and N2O.",
            "Blood-gas solubility determines speed of induction (N2O and desflurane fast; halothane slow). Halothane sensitises myocardium to catecholamines and can cause hepatitis.",
        ],
    )
    add(
        "Chest Radiology",
        "Silhouette sign, pneumonia and pneumothorax",
        "Explain the silhouette sign with examples. Add a note on radiological signs of pneumothorax.",
        10,
        [
            "The silhouette sign: loss of the outline of a soft-tissue structure when an adjacent opacity of similar density touches it.",
            "Right-middle-lobe consolidation silhouettes the right heart border; lingula the left heart border; lower-lobe lesions silhouette the hemidiaphragm.",
            "Lobar pneumonia shows air bronchograms and a lobar density; bronchopneumonia is patchy.",
            "Pneumothorax: visible visceral pleural line, absent peripheral lung markings, and in tension a contralateral mediastinal shift with a deep sulcus on a supine film.",
            "Erect CXR is more sensitive for small pneumoperitoneum (air under diaphragm) than for tiny pneumothorax — think in the right clinical context.",
            "Always compare with old films and remember rotation, poor inspiration and lordotic views as traps.",
        ],
    )
    add(
        "Forensic Thanatology",
        "Early signs of death and rigor mortis",
        "Describe rigor mortis. Add a note on cadaveric spasm and the early signs of death.",
        10,
        [
            "Somatic death is irreversible cessation of circulation and respiration. Early signs: cooling (algor), pallor, flaccidity, then rigor and hypostasis.",
            "Rigor is stiffening from ATP depletion and actin-myosin lock. It appears first in small muscles (eyelids, jaw) and spreads (Nysten), then passes in the same order.",
            "Onset is typically 1–2 h, well established by 12 h, and passes in 24–36 h depending on temperature (accelerated in heat, delayed in cold).",
            "Cadaveric spasm is instantaneous rigidity in a group of muscles at the moment of death (drowning victim clutching weeds) and has medicolegal value.",
            "Postmortem caloricity may occur in sepsis, sunstroke, tetanus and strychnine.",
            "Distinguish rigor from heat stiffening, cold stiffening and putrefactive gases.",
        ],
    )
    add(
        "Nephrology",
        "AKI, CKD and nephritic-nephrotic syndromes",
        "Classify AKI (KDIGO). Differentiate nephritic and nephrotic syndrome with one example each.",
        10,
        [
            "KDIGO AKI: rise in creatinine ≥0.3 mg/dL in 48 h, or ≥1.5× baseline in 7 days, or oliguria <0.5 mL/kg/h for 6 h.",
            "Pre-renal (hypoperfusion), intrinsic (ATN, AIN, GN, vascular) and post-renal (obstruction). FeNa and urine microscopy help once volume is assessed.",
            "CKD is >3 months of reduced GFR or kidney damage markers; stages G1–G5 by eGFR. Anaemia, bone mineral disease, acidosis and CV risk rise as GFR falls.",
            "Nephritic: haematuria, RBC casts, mild proteinuria, hypertension, oliguria — e.g. post-streptococcal GN, IgA nephropathy.",
            "Nephrotic: heavy proteinuria (>3.5 g/day), hypoalbuminaemia, oedema, hyperlipidaemia — e.g. minimal change in children, membranous in adults.",
            "Indications for urgent dialysis (AEIOU): acidosis, electrolytes (K+), intoxications, overload, uraemic complications (pericarditis, encephalopathy).",
        ],
    )
    add(
        "Breast and Endocrine Surgery",
        "Breast carcinoma",
        "Describe the clinical features and TNM staging principles of carcinoma breast. Add a note on triple assessment.",
        10,
        [
            "Breast cancer typically presents as a hard, irregular, non-tender lump, possibly with skin dimpling, nipple retraction, peau d'orange or axillary nodes.",
            "Triple assessment: clinical examination, imaging (mammogram ± ultrasound; MRI selected cases) and pathology (core biopsy preferred over FNAC for invasive disease).",
            "Most are invasive ductal (NST); lobular, tubular, mucinous are special types. Receptor status (ER, PR, HER2) and grade guide systemic therapy.",
            "TNM: T by size and chest-wall/skin involvement, N by nodal stations, M by distant disease. Sentinel-node biopsy is standard in clinically node-negative patients.",
            "Surgery is breast-conserving (with radiotherapy) or mastectomy; reconstruction is discussed. Axillary clearance if sentinel node is positive per protocol.",
            "Adjuvant endocrine therapy, anti-HER2 (trastuzumab) and chemotherapy according to risk. Screening mammography is for eligible age groups in organised programmes.",
        ],
    )
    return facts


def wiki_url(slug: str) -> str:
    return "https://en.wikipedia.org/wiki/" + slug


def medico_url(subject: str) -> str:
    return f"https://medico.shishal.com/kuhs/{SUBJECT_SLUG[subject]}/"


def paper_id(subject: str, year: int, paper_name: str, exam_type: str) -> str:
    slug = PREFIX[subject]
    if paper_name == "Paper II":
        pn = "P2"
    elif paper_name == "Paper I":
        pn = "P1"
    else:
        pn = "INT"
    if exam_type == "internal":
        return f"EP-KUHS-{slug}-{year}-INT"
    return f"EP-KUHS-{slug}-{year}-{pn}"


def build_exam_papers() -> list[dict]:
    rows = []
    two_paper = {
        "Anatomy",
        "Physiology",
        "Biochemistry",
        "Pathology",
        "Microbiology",
        "Pharmacology",
        "Community Medicine",
        "Medicine",
        "Surgery",
        "Obstetrics & Gynaecology",
        "Pediatrics",
    }
    for subject, _, _ in SUBJECTS:
        papers = ["Paper I", "Paper II"] if subject in two_paper else ["Paper I"]
        for year in (2021, 2022, 2023, 2024, 2025):
            for pn in papers:
                rows.append(
                    {
                        "external_id": paper_id(subject, year, pn, "university"),
                        "university_code": "KUHS",
                        "subject_name": subject,
                        "exam_year": year,
                        "paper_name": pn,
                        "exam_type": "university",
                    }
                )
        # One internal per subject so exam_type mix is testable.
        rows.append(
            {
                "external_id": paper_id(subject, 2024, "Paper I", "internal"),
                "university_code": "KUHS",
                "subject_name": subject,
                "exam_year": 2024,
                "paper_name": "Internal assessment I",
                "exam_type": "internal",
            }
        )
    return rows


def is_generated_id(external_id: str) -> bool:
    """True for rows this script owns, so a second run does not duplicate them."""
    if external_id in ("Q-ANAT-PYQ-001", "Q-ANAT-PYQ-002"):
        return False
    if re.match(r"^Q-[A-Z]+-PYQ-\d+$", external_id):
        return True
    if re.match(r"^Q-[A-Z]+-X-\d+$", external_id):
        return True
    return False


def sheet_header_key(name: str) -> str:
    """kind(Default-MCQ) → kind. Keep in sync with Apps Script headerKey_."""
    s = (name or "").strip().lstrip("\ufeff")
    s = re.sub(r"\s*\([^)]*default[^)]*\)", "", s, flags=re.I)
    return s.strip()


def read_existing_questions() -> list[dict]:
    path = TABS / "Questions.csv"
    # utf-8-sig strips a BOM that Google Sheets sometimes writes on export.
    with path.open(newline="", encoding="utf-8-sig") as fh:
        reader = csv.DictReader(fh)
        rows = list(reader)
    cleaned = []
    seen = set()
    for row in rows:
        keyed = {sheet_header_key(k): v for k, v in row.items()}
        ext = (keyed.get("external_id") or "").strip()
        if not ext or ext in seen or is_generated_id(ext):
            continue
        seen.add(ext)
        kind = (keyed.get("kind") or "").strip().lower()
        # Never round-trip theory rows (multiline sample answers shift columns).
        if kind == "pyq_theory" or ext.startswith("Q-") and "-PYQ-" in ext:
            continue
        if kind not in ("", "mcq"):
            continue
        cleaned.append(keyed)
    return cleaned


def write_csv(name: str, fieldnames: list[str], rows: list[dict]) -> None:
    path = TABS / name
    with path.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def question_combo_key(row: dict) -> tuple[str, ...]:
    """One sheet row per subject/topic/kind/difficulty/plan/year/paper/exam type."""
    kind = (row.get("kind(Default-MCQ)") or row.get("kind") or "").strip()
    difficulty = (
        row.get("difficulty(Default-should)") or row.get("difficulty") or ""
    ).strip()
    plan = (
        row.get("required_plan(Default-free)") or row.get("required_plan") or ""
    ).strip()
    exam_type = (
        row.get("exam_type(Default-university)") or row.get("exam_type") or ""
    ).strip()
    return (
        (row.get("subject_name") or "").strip(),
        (row.get("topic_name") or "").strip(),
        kind,
        difficulty,
        plan,
        str(row.get("exam_year") or "").strip(),
        (row.get("paper_name") or "").strip(),
        exam_type,
    )


def keep_first_combo(rows: list[dict]) -> list[dict]:
    seen: set[tuple[str, ...]] = set()
    kept: list[dict] = []
    for row in rows:
        key = question_combo_key(row)
        if key in seen:
            continue
        seen.add(key)
        kept.append(row)
    return kept


def keep_year1(rows: list[dict]) -> list[dict]:
    """Seed content is year 1 only until later years are filled in."""
    return [
        row
        for row in rows
        if (row.get("phase_code") or "").strip() == "year1"
    ]


def keep_should_priority(rows: list[dict]) -> list[dict]:
    """Seed rows all carry the default `should` priority (MoSCoW)."""
    return [
        row
        for row in rows
        if (
            row.get("difficulty(Default-should)") or row.get("difficulty") or ""
        ).strip().lower()
        == "should"
    ]


def keep_first_topic(rows: list[dict]) -> list[dict]:
    """One seed question per subject/topic until more coverage is needed."""
    seen: set[tuple[str, str]] = set()
    kept: list[dict] = []
    for row in rows:
        key = (
            (row.get("subject_name") or "").strip(),
            (row.get("topic_name") or "").strip(),
        )
        if key in seen:
            continue
        seen.add(key)
        kept.append(row)
    return kept


def appearance_years(topic_index: int, lesson_index: int, marks: int) -> list[int]:
    if marks >= 10:
        return [2025, 2023, 2021]
    if (topic_index + lesson_index) % 3 == 0:
        return [2024, 2022]
    return [2024]


def build() -> None:
    existing_q = read_existing_questions()
    existing_ids = {row["external_id"] for row in existing_q}

    lessons: list[dict] = []
    pyqs: list[dict] = []
    extra_mcqs: list[dict] = []
    lesson_resources: list[dict] = []
    textbook_refs: list[dict] = []
    question_resources: list[dict] = []
    lessons_by_topic: dict[str, list[str]] = defaultdict(list)

    custom = custom_pyq_facts()
    pyq_seq: dict[str, int] = defaultdict(int)
    xmcq_seq: dict[str, int] = defaultdict(int)
    seen_lesson_ids: set[str] = set()

    for topic_index, (subject, topic, _) in enumerate(TOPICS):
        names = LESSON_NAMES[topic]
        tb_key, tb_page = TOPIC_TEXTBOOK[topic]
        for lesson_index, (lesson_name, wiki) in enumerate(names):
            lid = lesson_id(topic, lesson_name)
            if lid in seen_lesson_ids:
                raise SystemExit(f"duplicate lesson id {lid} for {topic} / {lesson_name}")
            seen_lesson_ids.add(lid)
            plan = LOCKED_LESSON_PLANS.get(lid) or plan_for(topic_index, lesson_index)
            lessons.append(
                {
                    "external_id": lid,
                    "topic_name": topic,
                    "name": lesson_name,
                    "display_order": lesson_index + 1,
                    "required_plan": plan,
                    "is_active": "TRUE",
                    "sheet_external_id": invent_lesson_external_id(subject, topic, lesson_name),
                }
            )
            lessons_by_topic[topic].append(lid)

            lesson_resources.append(
                {
                    "subject_name": subject,
                    "topic_name": topic,
                    "lesson_name": lesson_name,
                    "title": f"{lesson_name} — KUHS topic page",
                    "url": medico_url(subject),
                    "source_label": "Medico topic page",
                    "display_order": 1,
                    "is_free": "TRUE",
                }
            )
            lesson_resources.append(
                {
                    "subject_name": subject,
                    "topic_name": topic,
                    "lesson_name": lesson_name,
                    "title": f"Read more: {lesson_name}",
                    "url": wiki_url(wiki.split("#")[0]),
                    "source_label": "Wikipedia (open reference)",
                    "display_order": 2,
                    "is_free": "TRUE" if lesson_index == 0 else "FALSE",
                }
            )

            # PYQ — keep the two already in the sheet.
            locked_pyq = LOCKED_PYQS.get(lid)
            marks = 10 if lesson_index == 0 else 5
            difficulty = "should" if marks == 10 else "could"
            if locked_pyq:
                qid = locked_pyq
            else:
                prefix = PREFIX[subject]
                pyq_seq[prefix] += 1
                # Anatomy 001/002 are locked.
                n = pyq_seq[prefix]
                if prefix == "ANAT":
                    n += 2
                qid = f"Q-{prefix}-PYQ-{n:03d}"
                stem, marks_c, bullets = custom.get(
                    lid, (pyq_stem(lesson_name, marks), marks, [])
                )
                if not bullets:
                    bullets = [
                        f"Open with a definition of {lesson_name.lower()} in one sentence.",
                        "Use numbered headings the examiner can tick: parts or steps, blood/nerve supply or mechanism, and one table of differences if relevant.",
                        "Add the single most common KUHS clinical correlation (palsy, deficiency, emergency drug, or surgical landmark).",
                        "Mention one investigation or applied anatomy fact that separates a pass from a distinction answer.",
                        "Close with complications or a related viva question (e.g. a labelled diagram or a difference from a neighbouring structure).",
                    ]
                    stem = pyq_stem(lesson_name, marks)
                    marks_c = marks
                else:
                    marks_c = marks_c
                is_custom = bool(bullets) and lid in custom
                skip_sample = (not is_custom) and (topic_index + lesson_index) % 9 == 3
                sample = None if skip_sample else compose_sample(lesson_name, bullets)
                q_plan = pyq_plan(plan, topic_index)
                pyqs.append(
                    {
                        "external_id": qid,
                        "topic_name": topic,
                        "question_text": stem,
                        "option_a": "",
                        "option_b": "",
                        "option_c": "",
                        "option_d": "",
                        "correct_option": "",
                        "explanation_text": "",
                        "explanation_video_url": "",
                        "image_url": "",
                        "difficulty": difficulty,
                        "source": "KUHS PYQ",
                        "required_plan": q_plan,
                        "is_active": "TRUE",
                        "kind": "pyq_theory",
                        "lesson_external_id": lid,
                        "marks": marks_c,
                        "sample_answer_text": sample or "",
                    }
                )

            textbook_refs.append(
                {
                    "question_external_id": qid,
                    "textbook_key": tb_key,
                    "page": tb_page + lesson_index * 12,
                    "section_heading": lesson_name,
                }
            )
            if lesson_index == 0:
                question_resources.append(
                    {
                        "question_external_id": qid,
                        "title": f"NMC-aligned note: {lesson_name}",
                        "url": medico_url(subject),
                        "source_label": "Medico",
                        "display_order": 1,
                        "is_free": "TRUE",
                    }
                )

    def append_extra(topic: str, lesson_name: str, lid: str, plan: str, lesson_index: int, mcq: tuple) -> None:
        subject = TOPIC_SUBJECT[topic]
        prefix = PREFIX[subject]
        stem, a, b, c, d, correct, expl, diff = mcq
        xmcq_seq[prefix] += 1
        xid = f"Q-{prefix}-X-{xmcq_seq[prefix]:03d}"
        while xid in existing_ids:
            xmcq_seq[prefix] += 1
            xid = f"Q-{prefix}-X-{xmcq_seq[prefix]:03d}"
        existing_ids.add(xid)
        extra_mcqs.append(
            {
                "external_id": xid,
                "topic_name": topic,
                "question_text": stem,
                "option_a": a,
                "option_b": b,
                "option_c": c,
                "option_d": d,
                "correct_option": correct,
                "explanation_text": expl,
                "explanation_video_url": "",
                "image_url": "",
                "difficulty": diff,
                "source": "KUHS / high-yield",
                "required_plan": "free" if lesson_index == 0 else plan,
                "is_active": "TRUE",
                "kind": "mcq",
                "lesson_external_id": lid,
                "marks": "",
                "sample_answer_text": "",
            }
        )

    # Authored extra MCQs (not the generic fallback).
    for L in lessons:
        key = f"{L['topic_name']}::{L['name']}"
        custom_bank = EXTRA_MCQS.get(key)
        if not custom_bank:
            continue
        for mcq in custom_bank:
            append_extra(
                L["topic_name"],
                L["name"],
                L["external_id"],
                L["required_plan"],
                int(L["display_order"]) - 1,
                mcq,
            )

    # Attach existing MCQs to lessons (keep any lesson_external_id already set).
    rr_index: dict[str, int] = defaultdict(int)
    merged_questions: list[dict] = []
    mcq_by_lesson: dict[str, int] = defaultdict(int)
    lesson_name_to_id = {(L["topic_name"], L["name"]): L["external_id"] for L in lessons}
    for row in existing_q:
        kind = (row.get("kind") or "mcq").strip().lower() or "mcq"
        if kind == "pyq_theory":
            merged_questions.append(row)
            continue
        topic = row.get("topic_name") or ""
        lids = lessons_by_topic.get(topic, [])
        current = (row.get("lesson_external_id") or "").strip()
        lesson_name = (row.get("lesson_name") or "").strip()
        mapped = lesson_name_to_id.get((topic, lesson_name)) if lesson_name else None
        if mapped:
            row = dict(row)
            row["lesson_external_id"] = mapped
            current = mapped
        elif (not current or current not in seen_lesson_ids) and lids:
            pick = lids[rr_index[topic] % len(lids)]
            rr_index[topic] += 1
            row = dict(row)
            row["lesson_external_id"] = pick
            current = pick
        if not (row.get("kind") or "").strip():
            row = dict(row)
            row["kind"] = "mcq"
        if current:
            mcq_by_lesson[current] += 1
        merged_questions.append(row)

    for q in extra_mcqs:
        mcq_by_lesson[q["lesson_external_id"]] += 1

    # Generic extras only when a lesson would otherwise have no practice MCQs.
    for L in lessons:
        lid = L["external_id"]
        if mcq_by_lesson[lid] >= 2:
            continue
        key = f"{L['topic_name']}::{L['name']}"
        if key in EXTRA_MCQS:
            continue
        for mcq in mcq_bank_for(L["topic_name"], L["name"]):
            if mcq_by_lesson[lid] >= 2:
                break
            append_extra(
                L["topic_name"],
                L["name"],
                lid,
                L["required_plan"],
                int(L["display_order"]) - 1,
                mcq,
            )
            mcq_by_lesson[lid] += 1

    merged_questions.extend(LOCKED_PYQ_ROWS)
    merged_questions.extend(pyqs)
    merged_questions.extend(extra_mcqs)

    papers = build_exam_papers()
    paper_by_subject: dict[str, list[dict]] = defaultdict(list)
    for p in papers:
        paper_by_subject[p["subject_name"]].append(p)

    appearances: list[dict] = []
    # Preserve the four original appearance rows for the locked PYQs, then
    # generate for every theory question.
    theory_rows = [q for q in merged_questions if (q.get("kind") or "").lower() == "pyq_theory"]
    seen_app = set()
    original_app = [
        ("Q-ANAT-PYQ-001", "EP-KUHS-ANAT-2024-P1"),
        ("Q-ANAT-PYQ-001", "EP-KUHS-ANAT-2023-P1"),
        ("Q-ANAT-PYQ-001", "EP-KUHS-ANAT-2021-P1"),
        ("Q-ANAT-PYQ-002", "EP-KUHS-ANAT-2024-P1"),
    ]
    for qid, pid in original_app:
        seen_app.add((qid, pid))
        appearances.append({"question_external_id": qid, "paper_external_id": pid})

    topic_index_map = {name: i for i, (_, name, _) in enumerate(TOPICS)}
    for q in theory_rows:
        qid = q["external_id"]
        subject = TOPIC_SUBJECT[q["topic_name"]]
        t_i = topic_index_map[q["topic_name"]]
        try:
            marks = int(q.get("marks") or 5)
        except ValueError:
            marks = 5
        years = appearance_years(t_i, 0, marks)
        candidates = [
            p
            for p in paper_by_subject[subject]
            if p["exam_type"] == "university" and p["exam_year"] in years
        ]
        if not candidates:
            candidates = [p for p in paper_by_subject[subject] if p["exam_type"] == "university"][:1]
        # Prefer Paper I when present.
        candidates = sorted(candidates, key=lambda p: (p["exam_year"], p["paper_name"]))
        picked = []
        for p in candidates:
            if p["paper_name"] == "Paper I" or len(picked) == 0:
                picked.append(p)
            if len(picked) >= (3 if marks >= 10 else 1):
                break
        if marks >= 10 and len(picked) < 2:
            picked = candidates[:3]
        for p in picked:
            key = (qid, p["external_id"])
            if key in seen_app:
                continue
            seen_app.add(key)
            appearances.append(
                {"question_external_id": qid, "paper_external_id": p["external_id"]}
            )

    # Static tabs
    write_csv(
        "Universities.csv",
        ["code", "name", "state"],
        [
            {"code": code, "name": name, "state": state}
            for code, name, state in UNIVERSITIES
        ],
    )
    write_csv(
        "Phases.csv",
        ["code", "name", "display_order"],
        [{"code": c, "name": n, "display_order": o} for c, n, o in PHASES],
    )
    college_rows = [
        {"university_code": "KUHS", "name": n} for n in COLLEGES
    ]
    for code, *_ in UNIVERSITIES:
        for name in STARTER_COLLEGES.get(code, []):
            college_rows.append({"university_code": code, "name": name})
        college_rows.append(
            {"university_code": code, "name": "Other / not listed"}
        )
    write_csv(
        "Colleges.csv",
        ["university_code", "name"],
        college_rows,
    )

    subject_phase = {n: p for n, _o, p in SUBJECTS}
    lesson_by_id = {L["external_id"]: L for L in lessons}
    paper_by_id = {p["external_id"]: p for p in papers}
    apps_by_q: dict[str, list[str]] = defaultdict(list)
    for a in appearances:
        apps_by_q[a["question_external_id"]].append(a["paper_external_id"])
    refs_by_q: dict[str, list[dict]] = defaultdict(list)
    for r in textbook_refs:
        refs_by_q[r["question_external_id"]].append(r)

    wide_fields = [
        "external_id",
        "university_code",
        "phase_code",
        "subject_name",
        "topic_name",
        "lesson_name",
        "kind(Default-MCQ)",
        "marks",
        "question_text",
        "option_a",
        "option_b",
        "option_c",
        "option_d",
        "correct_option",
        "explanation_text",
        "sample_answer_text",
        "difficulty(Default-should)",
        "required_plan(Default-free)",
        "is_active(Default-TRUE)",
        "exam_year",
        "paper_name",
        "exam_type(Default-university)",
        "textbook_key",
        "page",
        "section_heading",
    ]
    wide_rows: list[dict] = []
    seen_q = set()
    for q in merged_questions:
        ext = q.get("external_id") or ""
        lid = (q.get("lesson_external_id") or "").strip()
        lesson = lesson_by_id.get(lid)
        topic = q.get("topic_name") or (lesson["topic_name"] if lesson else "")
        subject = TOPIC_SUBJECT.get(topic, "")
        phase = subject_phase.get(subject, "")
        paper_ids = apps_by_q.get(ext) or [None]
        refs = refs_by_q.get(ext) or [None]
        for pid in paper_ids:
            paper = paper_by_id.get(pid) if pid else None
            for ref in refs:
                wide_rows.append(
                    {
                        "external_id": ext,
                        "university_code": (paper or {}).get("university_code") or "",
                        "phase_code": phase,
                        "subject_name": subject,
                        "topic_name": topic,
                        "lesson_name": lesson["name"] if lesson else "",
                        "kind(Default-MCQ)": q.get("kind") or "mcq",
                        "marks": q.get("marks") or "",
                        "question_text": q.get("question_text") or "",
                        "option_a": q.get("option_a") or "",
                        "option_b": q.get("option_b") or "",
                        "option_c": q.get("option_c") or "",
                        "option_d": q.get("option_d") or "",
                        "correct_option": q.get("correct_option") or "",
                        "explanation_text": q.get("explanation_text") or "",
                        "sample_answer_text": q.get("sample_answer_text") or "",
                        "difficulty(Default-should)": q.get("difficulty") or "should",
                        "required_plan(Default-free)": q.get("required_plan") or "free",
                        "is_active(Default-TRUE)": q.get("is_active") or "TRUE",
                        "exam_year": (paper or {}).get("exam_year") or "",
                        "paper_name": (paper or {}).get("paper_name") or "",
                        "exam_type(Default-university)": (paper or {}).get("exam_type") or "",
                        "textbook_key": (ref or {}).get("textbook_key") or "",
                        "page": (ref or {}).get("page") or "",
                        "section_heading": (ref or {}).get("section_heading") or "",
                    }
                )
        seen_q.add(ext)
    wide_rows = keep_first_topic(
        keep_should_priority(keep_year1(keep_first_combo(wide_rows)))
    )
    write_csv("Questions.csv", wide_fields, wide_rows)

    kept_lessons = {
        (
            (r.get("subject_name") or "").strip(),
            (r.get("topic_name") or "").strip(),
            (r.get("lesson_name") or "").strip(),
        )
        for r in wide_rows
    }
    write_csv(
        "LessonResources.csv",
        [
            "subject_name",
            "topic_name",
            "lesson_name",
            "title",
            "url",
            "source_label",
            "display_order(Default-1)",
            "is_free(Default-TRUE)",
        ],
        [
            {
                "subject_name": r["subject_name"],
                "topic_name": r["topic_name"],
                "lesson_name": r["lesson_name"],
                "title": r["title"],
                "url": r["url"],
                "source_label": r["source_label"],
                "display_order(Default-1)": r["display_order"],
                "is_free(Default-TRUE)": r["is_free"],
            }
            for r in lesson_resources
            if (
                (r["subject_name"] or "").strip(),
                (r["topic_name"] or "").strip(),
                (r["lesson_name"] or "").strip(),
            )
            in kept_lessons
        ],
    )
    cited_tb = {
        (r.get("textbook_key") or "").strip()
        for r in wide_rows
        if (r.get("textbook_key") or "").strip()
    }
    write_csv(
        "Textbooks.csv",
        ["sheet_key", "title", "authors", "edition"],
        [
            {"sheet_key": k, "title": t, "authors": a, "edition": e}
            for k, t, a, e in TEXTBOOKS
            if k in cited_tb
        ],
    )

    # Coverage report
    by_kind = defaultdict(int)
    mcq_by_lesson = defaultdict(int)
    pyq_by_lesson = defaultdict(int)
    for q in merged_questions:
        kind = (q.get("kind") or "mcq").strip().lower() or "mcq"
        by_kind[kind] += 1
        lid = (q.get("lesson_external_id") or "").strip()
        if not lid:
            continue
        if kind == "mcq":
            mcq_by_lesson[lid] += 1
        else:
            pyq_by_lesson[lid] += 1

    empty_mcq = [L["external_id"] for L in lessons if mcq_by_lesson[L["external_id"]] == 0]
    empty_pyq = [L["external_id"] for L in lessons if pyq_by_lesson[L["external_id"]] == 0]
    topics_without_lessons = [n for _, n, _ in TOPICS if n not in lessons_by_topic]

    print("Wrote wide seed CSVs to", TABS)
    print(f"  universities      {len(UNIVERSITIES)}")
    print(f"  colleges          {len(college_rows)}")
    print(f"  textbooks         {len(TEXTBOOKS)}")
    print(f"  lesson resources  {len(lesson_resources)}")
    print(f"  question rows     {len(wide_rows)}  (unique ids={len(seen_q)}, mcq={by_kind['mcq']}, pyq_theory={by_kind['pyq_theory']})")
    if topics_without_lessons:
        print("  ERROR topics with no lessons:", topics_without_lessons)
    if empty_pyq:
        print(f"  lessons missing PYQ ({len(empty_pyq)}):", empty_pyq[:8], "...")
    if empty_mcq:
        print(f"  lessons missing MCQ ({len(empty_mcq)}):", empty_mcq[:8], "...")

    retired = [
        "Subjects.csv",
        "Topics.csv",
        "Lessons.csv",
        "ExamPapers.csv",
        "Appearances.csv",
        "TextbookRefs.csv",
        "QuestionResources.csv",
        "QuestionOptions.csv",
        "Tests.csv",
        "TestQuestions.csv",
    ]
    for name in retired:
        path = TABS / name
        if path.exists():
            path.unlink()
            print(f"  removed retired tab {name}")


if __name__ == "__main__":
    build()
