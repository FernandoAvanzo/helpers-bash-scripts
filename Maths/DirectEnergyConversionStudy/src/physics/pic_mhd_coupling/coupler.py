
class PIC_MHD_Coupler:
    def __init__(self, pic_solver, mhd_solver):
        self.pic = pic_solver
        self.mhd = mhd_solver

    def step(self, dt):
        charge_density = self.pic.compute_charge_density()
        fields = self.mhd.solve_fields(charge_density)
        self.pic.push_particles(fields, dt)
        self.mhd.update_plasma_state(dt)
