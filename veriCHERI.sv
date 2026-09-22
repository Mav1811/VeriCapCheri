module property_checker(
input CLK,
input RST_N
);

default clocking default_clk @(posedge CLK); endclocking

//these two functions checks the access to the memory if it is enabled when the secret address is requested 
function automatic data_mem_access();
	data_mem_access =(
	(mkCPU.near_mem$dmem_req_addr != mkCPU.secret_address) || !mkCPU.near_mem$EN_dmem_req
  );
endfunction

function automatic instr_mem_access();
	instr_mem_access =(
	(mkCPU.near_mem$imem_req_addr != mkCPU.secret_address) || !mkCPU.near_mem$EN_imem_req
  );
endfunction




//This functino takes the required bits from the capability's bounds field and reconstructs the top bounds and returns it
function automatic logic [64:0] get_top(logic [1:0] cor_top, logic [13:0] top_bits, logic [63:0] addr, logic [5:0] exp);
	logic [64:0] addtop = {{49{cor_top[1]}}, cor_top[0], top_bits} << exp;
	logic [50:0] mask = (51'h7FFFFFFFFFFFF )<< exp ;
	logic [64:0] top1 = ( {{1'b0, addr[63:14]} & mask, 14'b0} ) + addtop;
	return top1;
	
	
	
endfunction

//This functino takes the required bits from the capability's bounds field and reconstructs the base bounds and returns it
function automatic logic [63:0] get_base(logic [1:0] cor_base, logic [13:0] base_bits, logic [63:0] addr, logic [5:0] exp);
	logic [63:0] addbase = {{48{cor_base[1]}}, cor_base[0], base_bits} << exp;
	logic [49:0] mask = (50'h3FFFFFFFFFFFF )<< exp;
	logic [63:0] base1 =  { addr[63:14] & mask, 14'b0}  + addbase;
	return base1;
endfunction

//set all the capabilities in the regfile to protect the secret address and to set the permissions of the capabilities 
function automatic gpr_protected();
	logic result = 1'b1;
	for(int i = 0; i < 32; i++) begin
		result = result && cap_protected(mkCPU.gpr_regfile.regfile.arr[i]);
	end
	return result;
endfunction;

//sets the capabilities in the SCR registers so that the secret address is protected
function automatic scr_protected();
	return cap_protected(mkCPU.csr_regfile.rg_mscratchc) && cap_protected(mkCPU.csr_regfile.rg_mtcc) && cap_protected(mkCPU.csr_regfile.rg_mtdc) && cap_protected(mkCPU.csr_regfile.rg_sepcc) && cap_protected(mkCPU.csr_regfile.rg_sscratchc)
	&& cap_protected(mkCPU.csr_regfile.rg_stcc) && cap_protected(mkCPU.csr_regfile.rg_stdc) && cap_protected(mkCPU.csr_regfile.rg_mepcc);
endfunction;

//sets all possible capabilitiy holding field/register in the stage2 buffer
function automatic stage2_capbilities_protected();
	return  cap_protected(mkCPU.stage2_rg_stage2[952:802]) && cap_protected(mkCPU.stage2_rg_stage2[791:641]) && cap_protected(mkCPU.stage2_rg_stage2[502:352]);
endfunction;
//sets all possible capabilitiy holding field/register in the stage3 buffer
function automatic stage3_capbilities_protected();
	return  cap_protected(mkCPU.stage3_rg_stage3[221:71]);
endfunction;

//set the pcc so that the secret address cannot be fetched or jumped to 
function automatic pcc_protected();
	return cap_protected(mkCPU.stage1_rg_pcc[224:74]);
endfunction;
//set the pcc so that the secret address cannot be fetched or jumped to 
function automatic next_pcc_protected();
	return cap_protected(mkCPU.rg_next_pcc[160:10]);
endfunction;

//set the ddc so that the secret address cannot be fetched or jumped to 
function automatic ddc_protected();
	return cap_protected(mkCPU.rg_ddc[160:10]);
endfunction;
//this register can hold capabilities when they are read from the SCR, one counterexample showed this register where it broke monotonicity 
function automatic rg_csr_val1_protected();
	return cap_protected(mkCPU.rg_csr_val1[160:10]);
endfunction;
//cap_protected takes a capabilitiy and sets all the fields in the capability so that the secret address is out of bounds(protecting it)
//and set the permissions so that the capability cannot manipulate other capabilities whether it is readin, writing, or executing 
function automatic cap_protected(logic [150:0] rg);
	logic [63:0] addr;
	logic [5:0] exp;
	logic [13:0] topbits;
	logic [13:0] basebits;
	logic [2:0] repbound;
	logic [2:0] tb ;
	logic [2:0] bb ;
	logic [2:0] ab ;
	logic Tophi;
	logic Basehi;
	logic addrhi;
	logic [2:0] repBound;
	logic [1:0] topCor;
	logic [1:0] baseCor;
	logic [64:0] topBound;
	logic [63:0] baseBound;
	logic top_gt_base;
	logic top_cor_correct;
	logic base_cor_correct;
	logic correct_addr_mid;
	logic secret_addr;
	logic iscap;
	logic uperms; 
	logic perms;
	logic otype;
	logic check_type_and_perms;
	logic secret_out_of_bounds;

	//specifying perms is not really necessary since the provers will look for a path to find a CEX
	iscap = rg[150] == 1'b1;
	uperms = rg[71:68] == 4'b0000;
	perms = rg[63:56] == 8'b00000000;
	otype = rg[52:35] != 18'b0;
	check_type_and_perms = uperms && perms && otype;

	addr = rg[149:86];
	exp = rg[33:28];
	topbits = rg[27:14];
	basebits = rg[13:0];

	correct_addr_mid = 14'(addr >> exp) == rg[95:82];

	tb = rg[27:25];
	bb = rg[13:11];
	ab = rg[85:83];
	repBound = bb - 1'b1;	

	Tophi = tb < repBound;
	Basehi = bb < repBound;
	addrhi = ab < repBound;

	if(Tophi == addrhi) begin
		topCor = 2'b00;
	end else if (Tophi && !addrhi) begin
		topCor = 2'b01;
	end else begin
		topCor = 2'b11;
	end

	if(Basehi == addrhi) begin
		baseCor = 2'b00;
	end else if( Basehi && !addrhi ) begin
		baseCor = 2'b01;
	end else begin
		baseCor = 2'b11;
	end
	
	//since the address range is reconstructed from the address in the cap, it is not necessary to specify that the address of the cap is not the symbolic address
	//secret_addr = addr == mkCPU.secret_address;
	
	
	topBound = get_top(topCor, topbits, addr, exp);
	baseBound = get_base(baseCor, basebits, addr, exp);
	
	top_gt_base = topBound > baseBound;
	secret_out_of_bounds = mkCPU.secret_address < baseBound || mkCPU.secret_address > topBound;
	return !iscap || 
		secret_out_of_bounds &&
		check_type_and_perms;

endfunction;

//sets the RAS to symbolic state without including the symbolic secret address 
function automatic init_ras();
	logic result = 1'b1;
	for(int i = 0; i < 16; i++) begin
		result = result && stageF_branch_predictor.rg_ras[ ((i+1)*65)-2: i*65 ] != mkCPU.secret_address;
	end
	return result;	
endfunction;

//sets the BTB to symbolic state without including the symbolic secret address 
function automatic init_btb();
	logic result = 1'b1;
	for(int i = 0; i< 256;i++) begin
		result = result && stageF_branch_predictor.btb_bramcore2.RAM[i][62:0] != mkCPU.secret_address[63:1] ;
	end
	for(int i = 256; i< 512;i++) begin
		result = result && stageF_branch_predictor.btb_bramcore2.RAM[i][62:0] != mkCPU.secret_address[63:1];
	end
	return result && stageF_branch_predictor.btb_bramcore2.DOB_R2[62:0] != mkCPU.secret_address[63:1] && stageF_branch_predictor.btb_bramcore2.DOB_R[62:0] != mkCPU.secret_address[63:1] 
			&& stageF_branch_predictor.btb_bramcore2.DOA_R2[62:0] != mkCPU.secret_address[63:1] && stageF_branch_predictor.btb_bramcore2.DOA_R[62:0] != mkCPU.secret_address[63:1];
endfunction;

//this function combines all other functions for setting all the capabilities to protect the secret address
function cheri_protected();
	return 
	scr_protected() &&
	next_pcc_protected() &&
	ddc_protected() &&
	gpr_protected() &&
	stage3_capbilities_protected() &&
	stage2_capbilities_protected() &&
	rg_csr_val1_protected() &&
	pcc_protected();
endfunction

	//****************************************//
	//***************properties***************//
	//****************************************//


//***********combine the confidentiality and integrity into one property **************

//this property currently is the conidentiality property of veriCHERI
//one safety property for the data cache
property one_safety_data();

	cheri_protected() 
	##1
	cheri_protected()
|->
	data_mem_access() 
;	
endproperty;

assert_one_safety_data: assert property( @(posedge CLK) disable iff (!RST_N) one_safety_data);


property monotonicity_step;
	mkCPU.rg_state == 4'b0011 && !mkCPU.near_mem.dmem_valid &&
	cheri_protected()
|=>
	cheri_protected()
	
endproperty;

monotnoicity_step_assertion: assert property(@(posedge CLK) disable iff(!RST_N) monotonicity_step);

//one-safety property for the instruction cache
property instr_mem_protected;
	init_ras() &&
	init_btb() &&
	cheri_protected() 
|=>
	instr_mem_access()
	
endproperty;

assert_instr_mem_protected: assert property(@(posedge CLK) disable iff(!RST_N) instr_mem_protected);


	//****************************************//
	//***************asumptions***************//
	//****************************************//

//make the symbolic address stable across all clock cycles
property stable_secret_address;
	$past(mkCPU.secret_address) == mkCPU.secret_address;
endproperty;

symbolic_address: assume property ( stable_secret_address);


//constraint the processor to be in pure capability mode
property pure_cap_mode;
	mkCPU.stage1_rg_pcc[129] == 1'b1;
endproperty;

//assume user mode only to prevent context switching 
Capbility_encoding_mode: assume property (@(posedge CLK) pure_cap_mode);
assume_u_mode: assume property( mkCPU.rg_cur_priv == 2'b00);

endmodule;
bind mkCPU property_checker checker_bind(.CLK(CLK), .RST_N(RST_N));